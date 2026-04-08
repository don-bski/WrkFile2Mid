## Proteus Preset Banks
This archive has preset banks for Emu Proteus 1, 2, and 3. See the text file in each zip for a content desctiption. The ID of your Proteus unit must be set to 00 to successfully load into the 'User Presets' locations 64 - 127. If you're currently using the factory defaults in these locations, you don't need to save them since the factory defaults are included here. Otherwise, save your user presets before loading any of these banks. **These banks WILL OVERWRITE the current user presets in locations 64 through 127!**

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

## Sysex Related Troubleshooting
**Problem 1:** You download and unzip the SYX files but are unable to load the presets into your Proteus unit. The computer software doesn't recognize a SYX file.</br>
**Answer:** Try a different Sysex dump utility program. Windows: `Bome SendSX` or `MIDI-OX`. Linux: `syxmidi` from this archive.

**Problem 2:** Unable to transfer a ppreset bank to Proteus. The MIDI indicator illuminates during the actual transfer. When the transfer completes, the Proteus still contains the previous presets in locations 64 - 127.</br>
**Answer:** Check the Unit ID setting on the Proteus unit. The unit ID is located by pressing the Proteus front panel Master button and scrolling with the Data knob. All preset banks in this archive were created using ID setting 00. Proteus must be set to ID 00 to load the preset banks. If you normally use a different unit ID in your setup, resave the patch bank using your ID setting. 

**Problem 3:** You are able to transfer individual presetss (265 bytes) from your computer to Proteus. When transfering a full preset bank (17k bytes), some or all of the presets don't work or sound incomplete.</br>
**Answer:** The computer based sequencer program may be sending the the Sysex data too fast for the Proteus. This generally results in parts of the Sysex data being lost. Check the sequencer software configuration settings for the ability to "slow down" the transmission of Sysex data. Cakewalk, for example, allows for the insertion of a delay both between sysex bytes and/or after a specified number of bytes have been sent. Check in your sequencer program documentation. 

**Problem 4:** You can transfer full preset banks (17k bytes) from computer to Proteus okay. Some of the presets don't sound like their name would imply or multiple presets sound the same.</br>
**Answer:** Make sure that the preset bank is the correct for your Proteus unit. A Proteus/2 preset bank will appear to load correctly but will not function properly on a Proteus/1. The Primary and Secondary waves specified in a preset must be available on your Proteus unit.

**Problem 5:** Your Proteus unit produces unexpected distortions after loading syxex data. Powering off/on the unit does not correct the problem. Attempts to reload factory presets does not correct the problem.</br>
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
    
**Problem 6:** Proteus still not working. What else can I check?</br>
**Answer:** All of the preset banks use SYX for the file type. If the sysex program requires a different file type, you can safely rename the file type as appropriate. The preset bank contents are in Proteus binary format and the file name/type is not used.

If the preset bank loads into the program, then the problem is related to the MIDI side. When you send the the preset bank, does the MIDI activity indicator on Proteus light? If not, then the sysex program isn't using your MIDI interface properly. I would check the program configuration settings for the MIDI port address and other parameters. Also check the MIDI cable connections. MIDI out from computer to midi in on Proteus.

**Problem 7:** Will Proteus/1 and Proteus/2 presets work on other Emu Proteus sound modules?</br>
**Answer:** You can load Proteus/1 and Proteus/2 presets into other Emu Proteus sound modules. Whether they will sound as intended depends on the fundamental sound entries contained in your Proteus wave table ROMs.

Each preset in the Proteus unit can be composed of up to 2 fundamental sounds; the primary and secondary. These settings for a particular preset can be viewed by pressing the `Edit` button on Proteus and turning the `Data` knob to display the `INSTRUMENT pri` and `INSTRUMENT sec` settings. The Proteus manual lists all of the fundamental sounds contained in the units sound ROMs. Lacking a manual, you can view the fundamental sound names using the Proteus front panel and the following procedure.
1. Press the `Edit` button on the front panel. 
2. Rotate the `Data` knob to display `INSTRUMENT pri`. 
3. Press the `Cursor` button to move cursor to the lower display line. 
4. Rotate the `Data` knob to display the sound wave number/names in the unit. 
5. Press the `Edit` button to exit edit mode. 

If the Proteus unit contains both of the fundamental sounds required by a particular preset, then the preset will sound correctly when loaded on the unit. If only one fundamental sound is present, then only the contribution that the fundamental makes to the overall preset will be heard. If neither fundamental sound is present, you will hear the sound of silence.

The Proteus units have a number of fundamental sounds in common with each other; especially the wave forms and overtone series. The newer units have some of the better fundamentals from the older units.

Experimenting could yield some unexpected and unique sounds. Who knows what you might get if you cross a woodwind preset with a bagpipe!  
