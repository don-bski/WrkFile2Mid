Preset banks for Emu Proteus 1, 2, and 3. See the text file in each zip for a content desctiption. The ID of your Proteus unit must be set to 00 to successfully load into the 'User Presets' locations 64-127. If you're currently using the factory defaults in these locations, you don't need to save them since the factory defaults are included here. Otherwise, save your user presets before loading any of these banks. **These banks WILL OVERWRITE the current user presets in locations 64 through 127!**

Use syxmidi and the following procedure to save the user presets using the Proteus front panel.
1. Ensure Proteus and computer are properly MIDI cable connected.
2. Press the Proteus `Master` button.
3. Use the `Data` knob to scroll to `SEND MIDI DATA`.
4. Use the `Cursor` button to select lower display line. The `Enter` button indicator will start flashing.
5. Use the `Data` knob to scroll to `User Presets`.
6. List the MIDI devices on the computer: `syxmidi -l`. (lowercase L) Note port cabled to Proteus; e.g. `hw:2,0,0`.
7. On computer, enter: `syxmidi -p hw:2,0,0 -r <file>`. Replace `<file>` with the desired name; e.g. myUserPresets.syx.  
8. On Proteus press the `Enter` button to send user presets 64-127 to syxmidi. Data is saved to the specified file.
9. On Proteus press the `Master` button.

**Problem:** Your Proteus unit produces unexpected distortions after loading syxex data. Powering off/on the unit does not correct the problem. Attempts to reload factory presets does not correct the problem.

**Answer:** Sysex data may have become corrupted during transmission to your Proteus unit. This is rare. The corrupted sysex data "scrambles" the Proteus NVRAM such that the internal processor can not properly function. A Diagnostic Mode Initialize may be needed to correct this condition.

**Proteus Initialization Procedure:**</br>
**WARNING!** The following procedure will reset ALL user configurable Proteus settings. Factory user presets will need to be reloaded and desired settings in `Master` will need to be re-entered.
1. Power off the Proteus unit. 
2. While pressing and holding down the `Master` and `Edit` buttons on the Proteus, power on the unit. 
3. The Proteus unit powers up and displays `DIAGNOSTICS`. 
4. Scroll through the diagnostic menu to the item `Initialize`. 
5. Press the `Enter` button to select the initialize function. 
6. Press `Enter` button again to perform the initialization.
7. When completed, power off/on the Proteus unit.
8. Press `Master` and re-enter the desired settings.
9. Reload the factory default presets to locations 64-127.
    
