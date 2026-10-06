// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

#include "CsiFilter.h"

namespace {

constexpr unsigned char kEsc = 0x1b;
constexpr unsigned char kCan = 0x18;
constexpr unsigned char kSub = 0x1a;

// CSI_ARGS_MAX from libvterm's vterm_internal.h. The parser writes
// args[++argi] on every separator, so 16 parameters stay in bounds and the
// separator that would open a seventeenth is suppressed instead.
constexpr int kMaxParams = 16;

bool isLeaderByte(unsigned char c) { return c >= 0x3c && c <= 0x3f; }
bool isIntermediate(unsigned char c) { return c >= 0x20 && c <= 0x2f; }
bool isFinalByte(unsigned char c) { return c >= 0x40 && c <= 0x7e; }

} // namespace

void CsiFilter::reset() {
    m_state = State::Ground;
    m_suppressing = false;
    m_separators = 0;
    m_afterIntermediate = false;
    m_inLeader = false;
}

size_t CsiFilter::push(char *data, size_t length) {
    size_t out = 0;
    for (size_t in = 0; in < length; ++in) {
        const unsigned char c = static_cast<unsigned char>(data[in]);
        bool emit = true;
        switch (m_state) {
        case State::Ground:
            // Everything passes; an ESC may begin a CSI.
            if (c == kEsc) m_state = State::Escape;
            break;
        case State::Escape:
            // '[' is hoisted to C1 CSI by libvterm (parser.c:185-196).
            // A bare ESC re-arms instead of ending anything.
            if (c == '[') {
                m_state = State::Csi;
                m_suppressing = false;
                m_separators = 0;
                m_afterIntermediate = false;
                m_inLeader = true;
            } else if (c != kEsc) {
                m_state = State::Ground;
            }
            break;
        case State::Csi:
            if (c == kEsc) {
                // ESC cancels the sequence and is reprocessed (parser.c:159).
                m_state = State::Escape;
            } else if (c == kCan || c == kSub) {
                m_state = State::Ground;
            } else if (c == ';') {
                if (m_afterIntermediate) m_state = State::Ground; // invalid there, argi frozen
                else if (m_suppressing) emit = false;
                else if (m_separators >= kMaxParams - 1) { m_suppressing = true; emit = false; }
                else { ++m_separators; m_inLeader = false; }
            } else if (c == ':') {
                // Sub-parameter separator: sets a flag only, never grows argi.
                if (m_afterIntermediate) m_state = State::Ground;
                else if (m_suppressing) emit = false;
                else m_inLeader = false;
            } else if (c >= '0' && c <= '9') {
                if (m_afterIntermediate) m_state = State::Ground;
                else { m_inLeader = false; if (m_suppressing) emit = false; }
            } else if (isLeaderByte(c)) {
                if (m_inLeader) break; // still accumulating the leader
                // Leader bytes after parameters started are invalid.
                if (m_suppressing) emit = false;
                m_state = State::Ground;
            } else if (isIntermediate(c)) {
                m_afterIntermediate = true;
                m_inLeader = false;
                if (m_suppressing) emit = false;
            } else if (isFinalByte(c)) {
                // Dispatch happens now with at most kMaxParams arguments;
                // forwarding it leaves libvterm's parser in a clean state.
                m_state = State::Ground;
            } else if (c == 0x00 || c == 0x7f || c < 0x20) {
                // NUL/DEL are ignored and other C0 controls are executed
                // inline without ending the sequence (parser.c:143-180).
            } else {
                // Any other byte invalidates the sequence (parser.c:256).
                if (m_suppressing) emit = false;
                m_state = State::Ground;
            }
            break;
        }
        if (emit) data[out++] = data[in];
    }
    return out;
}
