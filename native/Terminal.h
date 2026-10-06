// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

#pragma once
#include <QQuickPaintedItem>
#include <QSocketNotifier>
#include <QTemporaryDir>
#include <QTimer>
#include <QFont>
#include <QtQml/qqmlregistration.h>
#include <vterm.h>
#include "CsiFilter.h"

// A PTY-backed terminal. libvterm handles VT sequences, UTF-8 and mouse modes;
// Qt paints the cells on a transparent item inside the desktop card.
class Terminal : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY metricsChanged)
    Q_PROPERTY(int fontPixelSize READ fontPixelSize WRITE setFontPixelSize NOTIFY metricsChanged)
    Q_PROPERTY(QColor foreground READ foreground WRITE setForeground NOTIFY paletteChanged)
    Q_PROPERTY(QColor background READ background WRITE setBackground NOTIFY paletteChanged)
    Q_PROPERTY(QColor accent READ accent WRITE setAccent NOTIFY paletteChanged)
    Q_PROPERTY(QString boxes READ boxes WRITE setBoxes NOTIFY boxesChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int processId READ processId NOTIFY runningChanged)
    Q_PROPERTY(QString error READ error NOTIFY runningChanged)
    Q_PROPERTY(int columns READ columns NOTIFY sizeChanged)
    Q_PROPERTY(int rows READ rows NOTIFY sizeChanged)
    Q_PROPERTY(qreal cellWidth READ cellWidth NOTIFY metricsChanged)
    Q_PROPERTY(qreal cellHeight READ cellHeight NOTIFY metricsChanged)
public:
    explicit Terminal(QQuickItem *parent = nullptr);
    ~Terminal() override;
    void paint(QPainter *painter) override;
    QString fontFamily() const { return m_font.family(); }
    int fontPixelSize() const { return m_font.pixelSize(); }
    QColor foreground() const { return m_foreground; }
    QColor background() const { return m_background; }
    QColor accent() const { return m_accent; }
    QString boxes() const { return m_boxes; }
    bool enabled() const { return m_enabled; }
    bool running() const { return m_pid > 0; }
    int processId() const { return m_pid; }
    QString error() const { return m_error; }
    int columns() const { return m_columns; }
    int rows() const { return m_rows; }
    qreal cellWidth() const { return m_cellWidth; }
    qreal cellHeight() const { return m_cellHeight; }
    void setFontFamily(const QString &value);
    void setFontPixelSize(int value);
    void setForeground(const QColor &value);
    void setBackground(const QColor &value);
    void setAccent(const QColor &value);
    void setBoxes(const QString &value);
    void setEnabled(bool value);
    Q_INVOKABLE void restart();
    Q_INVOKABLE QString screenText() const;
signals:
    void metricsChanged();
    void paletteChanged();
    void boxesChanged();
    void enabledChanged();
    void runningChanged();
    void sizeChanged();
    void focusRequested();
protected:
    void componentComplete() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
private:
    void updateMetrics();
    void resizeTerminal();
    void readOutput();
    void writeInput(const char *bytes, size_t length);
    void flushInput();
    void stop();
    void reap();
    void prepareConfig();
    void updatePalette();
    void sendMouse(QPointF position, Qt::KeyboardModifiers modifiers, int button, bool pressed);
    QColor color(VTermColor value) const;
    static void output(const char *bytes, size_t length, void *data);
    static int damage(VTermRect rect, void *data);
    static int cursor(VTermPos pos, VTermPos old, int visible, void *data);
    VTerm *m_vterm = nullptr;
    VTermScreen *m_screen = nullptr;
    QFont m_font;
    QColor m_foreground = QColor("#c0caf5"), m_background = QColor("#1a1b26"), m_accent = QColor("#7aa2f7");
    qreal m_cellWidth = 8, m_cellHeight = 17, m_ascent = 13;
    int m_columns = 80, m_rows = 24;
    int m_fd = -1, m_pid = -1;
    bool m_enabled = false, m_complete = false, m_cursorVisible = false;
    VTermPos m_cursor{};
    QString m_boxes = "cpu mem net proc", m_error;
    QTemporaryDir m_directory;
    QSocketNotifier *m_readNotifier = nullptr, *m_writeNotifier = nullptr;
    CsiFilter m_filter;
    QByteArray m_pendingInput;
    QTimer m_reaper, m_paletteTimer;
};
