-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 ManateeLazyCat

-- Stable live geometry for this desktop card; other layers keep their animations.
hl.layer_rule({
  match = { namespace = "^omarchy-desktop-top(-input)?$" },
  no_anim = true,
  animation = "none",
})
