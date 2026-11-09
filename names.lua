-- Names (1.20): who someone is, on a client where characters have a first and a last name.
--
-- On Forever, chat and add-on messages give a sender as "First Last" ("Tyrant Kuma"), while the guild roster and
-- UnitName give only "First". A whisper to a first name alone fails ("No player named ..."). So there are two
-- questions, and two answers:
--   who is it?            Names.First(name): the key the roster uses, the same for every form of the name
--   how do I reach them?  Names:Address(nameOrUnit): the full name, from the unit or from what chat has shown us
--
-- Since 1.27 it is LibForever-1.0's Names (Names.lua in ForeverAPI's lib/), the same table; it learns names from chat
-- itself.

NorgannonCore.Names = NorgannonCore.LibForever.Names
