// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 ManateeLazyCat

#pragma once
#include <cstddef>

// Bounds CSI parameter counts before bytes reach libvterm.
//
// libvterm up to and including 0.3.3 increments its CSI argument index on
// every ';' and ':' - parser.c:229-235 rewrites a colon to a semicolon and
// falls through to the same argi++ - without checking CSI_ARGS_MAX
// (src/parser.c:233-235), so a sequence with more than 16 parameters writes
// past the long args[16] that
// ends the parser union and lands on the callback pointers stored behind it
// (src/vterm_internal.h:210-233). btop renders process argv without escaping
// control characters in tree view (src/btop_draw.cpp:2098-2101), so another
// local user can inject such a sequence through /proc/<pid>/cmdline and
// corrupt this process.
//
// This filter mirrors libvterm's CSI state machine (parser.c lines 143-259)
// and suppresses the sixteenth parameter separator together with the rest of
// that sequence. The terminating final byte is still forwarded, so the
// parser resumes cleanly with at most 16 arguments - the documented safe
// maximum. Every other byte passes through untouched: DCS/OSC payload
// lengths are bounded or dynamically allocated inside libvterm, and no other
// parser state grows an array from stream input.
//
// Bytes are emitted or dropped immediately, so output never exceeds input
// and push() may filter in place. State persists across calls because
// sequences straddle PTY read boundaries.
class CsiFilter {
public:
    // Filters |data| in place and returns the number of leading bytes that
    // are safe to hand to vterm_input_write().
    size_t push(char *data, size_t length);

    // Returns to the ground state, e.g. when the child is restarted and the
    // previous stream ended mid-sequence.
    void reset();

private:
    enum class State { Ground, Escape, Csi };
    State m_state = State::Ground;
    bool m_suppressing = false;        // inside a CSI that already hit the limit
    int m_separators = 0;              // ';' and ':' separators seen in the current CSI
    bool m_afterIntermediate = false;  // libvterm is in its CSI_INTERMED state
    bool m_inLeader = false;           // only leader bytes 0x3c-0x3f seen so far
};
