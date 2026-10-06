// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

#include "Terminal.h"
#include <QPainter>
#include <QFontMetricsF>
#include <QFile>
#include <QDir>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QInputMethodEvent>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QProcessEnvironment>
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

static VTermModifier modifiers(Qt::KeyboardModifiers value) {
    return static_cast<VTermModifier>((value.testFlag(Qt::ShiftModifier) ? VTERM_MOD_SHIFT : 0)
        | (value.testFlag(Qt::AltModifier) ? VTERM_MOD_ALT : 0)
        | (value.testFlag(Qt::ControlModifier) ? VTERM_MOD_CTRL : 0));
}

Terminal::Terminal(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAcceptedMouseButtons(Qt::LeftButton | Qt::MiddleButton | Qt::RightButton);
    setFlag(ItemAcceptsInputMethod, true);
    setAntialiasing(false);
    m_font.setFamily("monospace");
    m_font.setPixelSize(13);
    m_font.setStyleHint(QFont::Monospace);
    m_vterm = vterm_new(m_rows, m_columns);
    vterm_set_utf8(m_vterm, true);
    vterm_output_set_callback(m_vterm, output, this);
    m_screen = vterm_obtain_screen(m_vterm);
    vterm_screen_enable_altscreen(m_screen, true);
    static const VTermScreenCallbacks callbacks = {
        damage, nullptr, cursor, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    vterm_screen_set_callbacks(m_screen, &callbacks, this);
    vterm_screen_set_damage_merge(m_screen, VTERM_DAMAGE_SCREEN);
    vterm_screen_reset(m_screen, true);
    updateMetrics();
    m_reaper.setInterval(250);
    connect(&m_reaper, &QTimer::timeout, this, &Terminal::reap);
    m_paletteTimer.setSingleShot(true);
    m_paletteTimer.setInterval(150);
    connect(&m_paletteTimer, &QTimer::timeout, this, [this] {
        updatePalette();
        if (running()) {
            prepareConfig();
            // btop's SIGUSR2 reloads its private config and theme in place.
            kill(m_pid, SIGUSR2);
        }
    });
}

Terminal::~Terminal() {
    stop();
    vterm_free(m_vterm);
}

void Terminal::setFontFamily(const QString &value) {
    if (value == m_font.family()) return;
    m_font.setFamily(value);
    updateMetrics();
}
void Terminal::setFontPixelSize(int value) {
    value = std::clamp(value, 8, 32);
    if (value == m_font.pixelSize()) return;
    m_font.setPixelSize(value);
    updateMetrics();
}
void Terminal::setForeground(const QColor &value) {
    if (m_foreground == value) return;
    m_foreground = value;
    emit paletteChanged();
    m_paletteTimer.start();
}
void Terminal::setBackground(const QColor &value) {
    if (m_background == value) return;
    m_background = value;
    emit paletteChanged();
    m_paletteTimer.start();
}
void Terminal::setAccent(const QColor &value) {
    if (m_accent == value) return;
    m_accent = value;
    emit paletteChanged();
    m_paletteTimer.start();
}
void Terminal::setBoxes(const QString &value) {
    if (m_boxes == value) return;
    m_boxes = value;
    emit boxesChanged();
    if (running()) m_paletteTimer.start();
}
void Terminal::setEnabled(bool value) {
    if (m_enabled == value) return;
    m_enabled = value;
    emit enabledChanged();
    if (!value) stop();
    else if (m_complete) QTimer::singleShot(0, this, &Terminal::restart);
}
void Terminal::componentComplete() {
    QQuickPaintedItem::componentComplete();
    m_complete = true;
    if (m_enabled) QTimer::singleShot(0, this, &Terminal::restart);
}
void Terminal::updateMetrics() {
    QFontMetricsF metrics(m_font);
    // Integral logical cells avoid gaps in box-drawing glyphs and rounding
    // below the required terminal size at fractional monitor scales.
    m_cellWidth = std::ceil(metrics.horizontalAdvance(QLatin1Char('M')));
    m_cellHeight = std::ceil(metrics.height());
    m_ascent = metrics.ascent();
    emit metricsChanged();
    resizeTerminal();
    update();
}
void Terminal::geometryChange(const QRectF &next, const QRectF &previous) {
    QQuickPaintedItem::geometryChange(next, previous);
    resizeTerminal();
}
void Terminal::resizeTerminal() {
    int columns = std::max(1, int(std::floor(width() / m_cellWidth)));
    int rows = std::max(1, int(std::floor(height() / m_cellHeight)));
    if (columns == m_columns && rows == m_rows) return;
    m_columns = columns;
    m_rows = rows;
    vterm_set_size(m_vterm, rows, columns);
    if (m_fd >= 0) {
        winsize size{};
        size.ws_col = columns; size.ws_row = rows;
        ioctl(m_fd, TIOCSWINSZ, &size); // Kernel sends SIGWINCH to the PTY group.
    }
    vterm_screen_flush_damage(m_screen);
    emit sizeChanged();
    update();
}

static QString replaceOption(QString config, const QString &key, const QString &value) {
    const QRegularExpression pattern("(?m)^" + QRegularExpression::escape(key) + "\\s*=.*$");
    if (config.contains(pattern)) config.replace(pattern, key + " = " + value);
    else config += "\n" + key + " = " + value + "\n";
    return config;
}
void Terminal::prepareConfig() {
    const QString configRoot = qEnvironmentVariable("XDG_CONFIG_HOME", QDir::homePath() + "/.config");
    QFile original(configRoot + "/btop/btop.conf");
    QString config;
    if (original.open(QIODevice::ReadOnly)) config = QString::fromUtf8(original.readAll());
    const QList<QPair<QString, QString>> overrides = {
        {"color_theme", "\"desktop-top\""}, {"theme_background", "false"},
        {"save_config_on_exit", "false"}, {"shown_boxes", "\"" + m_boxes + "\""},
        {"terminal_sync", "false"}, {"truecolor", "true"}, {"tty_mode", "false"},
        {"disable_mouse", "false"}, {"update_ms", "1000"}};
    for (const auto &entry : overrides) config = replaceOption(config, entry.first, entry.second);
    QFile privateConfig(m_directory.filePath("btop.conf"));
    if (privateConfig.open(QIODevice::WriteOnly | QIODevice::Truncate)) privateConfig.write(config.toUtf8());
    // Use the full active btop palette when available, while matching the
    // card's theme foreground and accent even for a theme without btop colors.
    QFile originalTheme(configRoot + "/btop/themes/current.theme");
    QString theme;
    if (originalTheme.open(QIODevice::ReadOnly)) theme = QString::fromUtf8(originalTheme.readAll());
    const QList<QPair<QString, QString>> colors = {
        {"main_bg", ""}, {"main_fg", m_foreground.name()}, {"title", m_foreground.name()},
        {"hi_fg", m_accent.name()}, {"selected_fg", m_accent.name()},
        {"cpu_box", m_accent.name()}, {"mem_box", m_accent.name()},
        {"net_box", m_accent.name()}, {"proc_box", m_accent.name()}};
    for (const auto &entry : colors) {
        const QString key = "theme[" + entry.first + "]";
        theme = replaceOption(theme, key, "\"" + entry.second + "\"");
    }
    QFile privateTheme(m_directory.filePath("desktop-top.theme"));
    if (privateTheme.open(QIODevice::WriteOnly | QIODevice::Truncate)) privateTheme.write(theme.toUtf8());
}
void Terminal::updatePalette() {
    VTermColor foreground, background;
    vterm_color_rgb(&foreground, m_foreground.red(), m_foreground.green(), m_foreground.blue());
    vterm_color_rgb(&background, m_background.red(), m_background.green(), m_background.blue());
    vterm_screen_set_default_colors(m_screen, &foreground, &background);
    update();
}

void Terminal::restart() {
    if (!m_enabled) return;
    stop();
    const QString binary = QStandardPaths::findExecutable("btop");
    if (binary.isEmpty() || !m_directory.isValid()) {
        m_error = binary.isEmpty() ? "btop executable not found" : "Cannot create btop runtime directory";
        emit runningChanged();
        return;
    }
    m_paletteTimer.stop();
    updatePalette();
    prepareConfig();
    vterm_screen_reset(m_screen, true);
    m_error.clear();
    // Prepare allocations before forking; the child only invokes Unix APIs.
    const QList<QByteArray> args = {binary.toLocal8Bit(), "--config", m_directory.filePath("btop.conf").toLocal8Bit(),
        "--themes-dir", m_directory.path().toLocal8Bit(), "--no-tty", "--force-utf"};
    std::vector<char *> argv;
    for (const auto &arg : args) argv.push_back(const_cast<char *>(arg.constData()));
    argv.push_back(nullptr);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert("TERM", "xterm-256color");
    env.insert("COLORTERM", "truecolor");
    env.insert("XDG_STATE_HOME", m_directory.path());
    env.insert("LC_ALL", "C.UTF-8");
    QList<QByteArray> entries;
    for (const auto &key : env.keys()) entries.append((key + "=" + env.value(key)).toLocal8Bit());
    std::vector<char *> envp;
    for (const auto &entry : entries) envp.push_back(const_cast<char *>(entry.constData()));
    envp.push_back(nullptr);
    winsize size{};
    size.ws_col = m_columns; size.ws_row = m_rows;
    const pid_t parent = getpid();
    const pid_t child = forkpty(&m_fd, nullptr, nullptr, &size);
    if (child == 0) {
        prctl(PR_SET_PDEATHSIG, SIGHUP);
        if (getppid() != parent) _exit(1);
        execve(argv[0], argv.data(), envp.data());
        _exit(127);
    }
    if (child < 0) {
        m_error = QString::fromLocal8Bit(strerror(errno));
        m_fd = -1;
        emit runningChanged();
        return;
    }
    m_pid = child;
    fcntl(m_fd, F_SETFL, fcntl(m_fd, F_GETFL) | O_NONBLOCK);
    fcntl(m_fd, F_SETFD, FD_CLOEXEC);
    m_filter.reset();
    m_readNotifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_readNotifier, &QSocketNotifier::activated, this, &Terminal::readOutput);
    m_writeNotifier = new QSocketNotifier(m_fd, QSocketNotifier::Write, this);
    m_writeNotifier->setEnabled(false);
    connect(m_writeNotifier, &QSocketNotifier::activated, this, &Terminal::flushInput);
    m_reaper.start();
    emit runningChanged();
}
void Terminal::stop() {
    m_reaper.stop();
    delete m_readNotifier; m_readNotifier = nullptr;
    delete m_writeNotifier; m_writeNotifier = nullptr;
    m_pendingInput.clear();
    if (m_pid > 0) {
        // Terminate the session as well as btop, and reap the child. No shell
        // or detached process survives plugin disable/hot reload.
        kill(-m_pid, SIGTERM);
        for (int i = 0; i < 20; ++i) {
            const auto result = waitpid(m_pid, nullptr, WNOHANG);
            if (result == m_pid || (result < 0 && errno == ECHILD)) { m_pid = -1; break; }
            usleep(5000);
        }
        if (m_pid > 0) { kill(-m_pid, SIGKILL); waitpid(m_pid, nullptr, 0); }
    }
    m_pid = -1;
    if (m_fd >= 0) close(m_fd);
    m_fd = -1;
    emit runningChanged();
}
void Terminal::reap() {
    if (m_pid <= 0) return;
    int status = 0;
    if (waitpid(m_pid, &status, WNOHANG) != m_pid) return;
    m_pid = -1;
    stop();
    m_error = WIFEXITED(status) && WEXITSTATUS(status) == 0 ? QString()
        : QString("btop exited (%1)").arg(WIFEXITED(status) ? WEXITSTATUS(status) : WTERMSIG(status));
    emit runningChanged();
    update();
}
void Terminal::readOutput() {
    char buffer[65536];
    // Bound each activation so a busy terminal cannot starve drag events.
    for (int i = 0; i < 8; ++i) {
        const ssize_t count = read(m_fd, buffer, sizeof(buffer));
        if (count > 0) {
            // btop tree view emits unescaped argv, so a local process can inject
            // CSIs with more parameters than libvterm's fixed argument array
            // holds. The filter clamps those at the boundary before parsing.
            const size_t safe = m_filter.push(buffer, size_t(count));
            if (safe > 0) vterm_input_write(m_vterm, buffer, safe);
        }
        else if (count < 0 && errno == EINTR) continue;
        else {
            if (count == 0 || (count < 0 && errno == EIO)) m_readNotifier->setEnabled(false);
            break;
        }
    }
    vterm_screen_flush_damage(m_screen);
}
void Terminal::writeInput(const char *bytes, size_t length) {
    if (m_fd < 0) return;
    m_pendingInput.append(bytes, length);
    flushInput();
}
void Terminal::flushInput() {
    while (m_fd >= 0 && !m_pendingInput.isEmpty()) {
        ssize_t count = write(m_fd, m_pendingInput.constData(), m_pendingInput.size());
        if (count > 0) m_pendingInput.remove(0, count);
        else if (count < 0 && errno == EINTR) continue;
        else break;
    }
    if (m_writeNotifier) m_writeNotifier->setEnabled(!m_pendingInput.isEmpty());
}
void Terminal::output(const char *bytes, size_t length, void *data) {
    static_cast<Terminal *>(data)->writeInput(bytes, length);
}
int Terminal::damage(VTermRect, void *data) { static_cast<Terminal *>(data)->update(); return 1; }
int Terminal::cursor(VTermPos pos, VTermPos, int visible, void *data) {
    auto *term = static_cast<Terminal *>(data);
    term->m_cursor = pos; term->m_cursorVisible = visible;
    term->update(); return 1;
}
QColor Terminal::color(VTermColor value) const {
    if (VTERM_COLOR_IS_DEFAULT_FG(&value)) return m_foreground;
    if (VTERM_COLOR_IS_DEFAULT_BG(&value)) return Qt::transparent;
    vterm_screen_convert_color_to_rgb(m_screen, &value);
    return QColor(value.rgb.red, value.rgb.green, value.rgb.blue);
}
void Terminal::paint(QPainter *painter) {
    painter->setRenderHint(QPainter::TextAntialiasing);
    for (int row = 0; row < m_rows; ++row) {
        for (int col = 0; col < m_columns; ++col) {
            VTermScreenCell cell{};
            if (!vterm_screen_get_cell(m_screen, {row, col}, &cell) || cell.chars[0] == UINT32_MAX) continue;
            QColor fg = color(cell.fg), bg = color(cell.bg);
            if (cell.attrs.reverse) { if (bg.alpha() == 0) bg = m_background; std::swap(fg, bg); }
            const QRectF rect(col * m_cellWidth, row * m_cellHeight, m_cellWidth * std::max(1, int(cell.width)), m_cellHeight);
            if (bg.alpha() > 0) painter->fillRect(rect, bg);
            if (!cell.chars[0] || cell.attrs.conceal) continue;
            QFont font = m_font;
            font.setBold(cell.attrs.bold); font.setItalic(cell.attrs.italic);
            font.setUnderline(cell.attrs.underline); font.setStrikeOut(cell.attrs.strike);
            painter->setFont(font); painter->setPen(fg);
            int length = 0;
            while (length < VTERM_MAX_CHARS_PER_CELL && cell.chars[length]) ++length;
            const QString text = QString::fromUcs4(reinterpret_cast<const char32_t *>(cell.chars), length);
            painter->drawText(QPointF(rect.x(), rect.y() + m_ascent), text);
        }
    }
    if (m_cursorVisible && hasActiveFocus()) {
        painter->fillRect(QRectF(m_cursor.col * m_cellWidth, (m_cursor.row + 1) * m_cellHeight - 2, m_cellWidth, 2), m_accent);
    }
}
QString Terminal::screenText() const {
    QByteArray text(m_rows * m_columns * 24 + m_rows, '\0');
    const auto length = vterm_screen_get_text(m_screen, text.data(), text.size(), {0, m_rows, 0, m_columns});
    return QString::fromUtf8(text.constData(), length);
}
void Terminal::keyPressEvent(QKeyEvent *event) {
    VTermKey key = VTERM_KEY_NONE;
    switch (event->key()) {
    case Qt::Key_Return: case Qt::Key_Enter: key = VTERM_KEY_ENTER; break;
    case Qt::Key_Tab: case Qt::Key_Backtab: key = VTERM_KEY_TAB; break;
    case Qt::Key_Backspace: key = VTERM_KEY_BACKSPACE; break;
    case Qt::Key_Escape: key = VTERM_KEY_ESCAPE; break;
    case Qt::Key_Up: key = VTERM_KEY_UP; break;
    case Qt::Key_Down: key = VTERM_KEY_DOWN; break;
    case Qt::Key_Left: key = VTERM_KEY_LEFT; break;
    case Qt::Key_Right: key = VTERM_KEY_RIGHT; break;
    case Qt::Key_Insert: key = VTERM_KEY_INS; break;
    case Qt::Key_Delete: key = VTERM_KEY_DEL; break;
    case Qt::Key_Home: key = VTERM_KEY_HOME; break;
    case Qt::Key_End: key = VTERM_KEY_END; break;
    case Qt::Key_PageUp: key = VTERM_KEY_PAGEUP; break;
    case Qt::Key_PageDown: key = VTERM_KEY_PAGEDOWN; break;
    default:
        if (event->key() >= Qt::Key_F1 && event->key() <= Qt::Key_F35)
            key = static_cast<VTermKey>(VTERM_KEY_FUNCTION(event->key() - Qt::Key_F1 + 1));
    }
    if (key != VTERM_KEY_NONE) vterm_keyboard_key(m_vterm, key, modifiers(event->modifiers()));
    else {
        const auto codepoints = event->text().toUcs4();
        for (const auto code : codepoints) vterm_keyboard_unichar(m_vterm, code, modifiers(event->modifiers()));
    }
    event->accept();
}
void Terminal::sendMouse(QPointF position, Qt::KeyboardModifiers mods, int button, bool pressed) {
    vterm_mouse_move(m_vterm, std::clamp(int(position.y() / m_cellHeight), 0, m_rows - 1),
        std::clamp(int(position.x() / m_cellWidth), 0, m_columns - 1), modifiers(mods));
    if (button) vterm_mouse_button(m_vterm, button, pressed, modifiers(mods));
}
static int mouseButton(Qt::MouseButton button) {
    return button == Qt::LeftButton ? 1 : button == Qt::MiddleButton ? 2 : button == Qt::RightButton ? 3 : 0;
}
void Terminal::mousePressEvent(QMouseEvent *event) {
    emit focusRequested();
    forceActiveFocus(Qt::MouseFocusReason);
    sendMouse(event->position(), event->modifiers(), mouseButton(event->button()), true);
    event->accept();
}
void Terminal::mouseReleaseEvent(QMouseEvent *event) {
    sendMouse(event->position(), event->modifiers(), mouseButton(event->button()), false);
    event->accept();
}
void Terminal::mouseMoveEvent(QMouseEvent *event) {
    sendMouse(event->position(), event->modifiers(), 0, false); event->accept();
}
void Terminal::wheelEvent(QWheelEvent *event) {
    const int button = event->angleDelta().y() >= 0 ? 4 : 5;
    for (int i = 0; i < std::max(1, std::abs(event->angleDelta().y()) / 120); ++i) {
        sendMouse(event->position(), event->modifiers(), button, true);
        sendMouse(event->position(), event->modifiers(), button, false);
    }
    event->accept();
}
void Terminal::focusInEvent(QFocusEvent *event) {
    QQuickPaintedItem::focusInEvent(event);
    vterm_state_focus_in(vterm_obtain_state(m_vterm)); update();
}
void Terminal::focusOutEvent(QFocusEvent *event) {
    QQuickPaintedItem::focusOutEvent(event);
    vterm_state_focus_out(vterm_obtain_state(m_vterm)); update();
}
void Terminal::inputMethodEvent(QInputMethodEvent *event) {
    for (auto code : event->commitString().toUcs4()) vterm_keyboard_unichar(m_vterm, code, VTERM_MOD_NONE);
    event->accept();
}
QVariant Terminal::inputMethodQuery(Qt::InputMethodQuery query) const {
    if (query == Qt::ImEnabled) return true;
    if (query == Qt::ImCursorRectangle)
        return QRectF(m_cursor.col * m_cellWidth, m_cursor.row * m_cellHeight, m_cellWidth, m_cellHeight);
    return QQuickPaintedItem::inputMethodQuery(query);
}
