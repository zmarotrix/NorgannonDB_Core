-- Core.Net (1.21): add-on messages under an add-on's own prefix, from Council's Transport: compression, a lockdown
-- queue, a real test send, and whispers to full names.
--
--   local ch = Core.Net:Channel("Council", { onMessage = function(text, first, sender, distribution) end })
--   ch:Send(text, "GUILD")
--
-- Since 1.28 it is LibForever-1.0's Net (Net.lua in ForeverAPI's lib/), the same table.

NorgannonCore.Net = NorgannonCore.LibForever.Net
