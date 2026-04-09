#!/usr/bin/perl
# ==============================================================================
# FILE: WrkFile2Mid.pl                                                4-09-2026
#
# SERVICES: Parse Cakewalk WRK file.  
#
# DESCRIPTION:
#   This program parses Cakewalk WRK files. This file type was used with early 
#   versions of the Twelve-Tone Cakewalk MIDI Sequencer program. In addition to
#   sequence related musical note data, WRK files can also hold device specific
#   system exclusive (sysex) data. This data is stored in a sysex bank area
#   within the WRK file. Both of these data can be saved to individual files
#   for subsequent use by a digital audio workstation (DAW) or MIDI sequencer.
#
#   Cakewalk WRK file data is stored in 'chunks'. Each has a unique identifier 
#   and data structure. Many of these chunks contain Cakewalk specific data that
#   is not needed by standard MIDI files. Any chunk identifiers that are not 
#   defined in the %WrkData hash are ignored. Each chunk processor describes the 
#   expected chunk data structure. Refer to the hash descriptions below for the 
#   extracted data content.
#
#   The MIDI file output has been tested with rosegarden and pmidi on Linux mint.
#   Use of the sysex data was more challenging due to the need to slow down the 
#   data transfer rate for my older Emu equipment. A number of Linux programs 
#   with ALSA connectivity were tried but none provided the ability to insert a 
#   byte-to-byte time delay during sysex transmission. A small C language tool
#   was created, syxmidi, to fill this need. Syxmidi can be used standalone or 
#   as integrated with this program's -s option.
#
#   Twelve Tone Cakewalk, and the WRK file, conform to the MIDI 1.0 standard. In
#   this standard, a MIDI port connection has 16 channels. More than 16 channels
#   requires multiple MIDI ports. An early interfacing product was the MPU-401.
#   It provided 2 MIDI ports of 16 channels each. Modern USB MIDI connections
#   have a similar architecture. In support of this, the MIDI standard provides
#   a meta-event that is placed in each MIDI track. It serves to identify the
#   MIDI port used for the transmission of the MIDI event data.
#
#   The newer MIDI standard changed this meta-event. The older meta-event, 00
#   FF 20 01 <p> is now deprecated. The WrkFile2Mid program uses this older
#   meta-data as it better aligns with the Twelve Tone Cakewalk WRK file. This
#   is an area of possible future program upgrade. The Linux pmidi tool, which
#   directly supports the older meta-data version, was used for WrkFile2Mid 
#   development testing of multiple MIDI ports.
#
#   The pmidi program, if not already present, is installed using the Linux 
#   package manager. e.g. 'sudo apt install pmidi'. Multiple MIDI ports are 
#   specified using its -p option. e.g. pmidi -p 24:0,24:1 file.mid. The only
#   anomaly I've noticed is the playback tempo is slower when compared to the
#   rosegarden sequencer on the same computer. Likely pmidi is not configuring
#   an event timer properly.
#
#   Syxmidi is a small C language tool that is integrated with this version of 
#   WrkFile2Mid. It provides the needed interfacing functions to the ALSA rawmidi
#   API. These functions are only used with the WrkFile2Mid -m, -M, and -s options. 
#   Syxmidi is a Linux only program at this time. See the syxmidi documentation
#   for build details. The syxmidi executable should be located in the WrkFile2Mid
#   directory. Long term plan is to replace syxmidi integration with the MIDI::
#   RtMidi::FFI::Device module once it implements the needed rawmidi functions.
#
#   There is a lot of debug messaging code (-d) that was used to learn the ins
#   and outs of WRK and MIDI files during program developemt. It was left in for 
#   future needs since it has insignificant performance impact on this program. 
#
#   To simplify display of debug message information, the input WRK file data is 
#   converted to an array of hex text bytes for internal processing. This does
#   result in extra sprintf() and hex() operations throughout the program.
#
#   References:
#   Chunk data were inferred from the drumsticl 2.11.0 C++ MIDI libraries at 
#   https://drumstick.sourceforge.io/docs/group__WRK.html and downloaded from 
#   https://sourceforge.net/projects/drumstick/files/2.11.0/drumstick-2.11.0.zip.
#
#   Note: A drumsticl bug was found with chunkId '2D' NSTREAM_CHUNK. Event count
#   should be int32, not int16.
#
#   See https://midi.org/midi-1-0-detailed-specification for the MIDI file 
#   specification.
#
#   The WrkFile2Mid.pm file holds support code for this program. See note below
#   on how it is added at perl runtime. Windows Strawberry perl can't locate the
#   module unless 'eval' method is used.
# ==============================================================================
#use strict;
use warnings;
use Getopt::Std;
use Cwd;
use File::Basename;
# use MIDI::RtMidi::FFI::Device;

# ==============================================================================
# Global Variables
our ($ExecutableName) = ($0 =~ /([^\/\\]*)$/);

# --- Add start directory to @INC for executable included perl module.
our $WorkingDir;
if ($0 =~ m#^(.+)$ExecutableName$#) {
   $WorkingDir = $1;
}
else {
   $WorkingDir = cwd();
}
unshift (@INC, $WorkingDir);

#  Use eval to add the WrkFile2Mid.pm module in the Windows environment. It's
#  done here after $WorkingDir is added to @INC so the module is found by perl.
#  This interferes with syntax error reporting in linux so normal 'use' for 
#  non-Windows environments.
eval "use WrkFile2Mid" if ($^O =~ m/Win/i);
use if $^O !~ m/Win/i, WrkFile2Mid;

our %cliOpts = ();                                # CLI options working hash
getopts('hauvefmnM:p:s:d:c:t:x:z:', \%cliOpts);   # Load CLI options hash
our $Syxmidi = join('/', $WorkingDir, 'syxmidi'); # syxmidi tool.
our $Version = 'v0.1';                            # Program version string.

# The following hashs holds WRK file global data. Various chunck processors store
# data here. The primary used entries are 'version' and 'timebase'.
our %WrkGlobal = ('version' => '', 'timebase' => 120);

# The following hash holds WRK file meter values as set by the METER_CHUNK and
# METERKEY_CHUNK chunks. The index is the effective measure (bar). The meter value 
# is expressed as 'sig_numerator:sig_demonimator'; e.g. 3:4 for 3/4 musical time. 
# The METERKEY_CHUNK entries 'measure:sig_numerator:sig_demonimator:keySig' include
# a third key signature value. See %KeySig for value meaning.
our %MeterData = ();

# The following hash holds WRK file tempo values as set by the TEMPO_CHUNK and 
# NTEMPO_CHUNK chunks. The index is the effective time of the value. The tempo 
# value is expressed as a decimal float xxx.yy value.  e.g. 16000 = 160.00 bpm, 
# 12325 = 123.25 bpm.
our %TempoData = ();

# The following hash holds WRK file data specified by one or more VARIABLE_CHUNK or
# COMMENT_CHUNK chunks. The hash key is the entry order occurance. (1, 2, ...)
our %WrkVariables = ();

# The following hash holds WRK file data specified by one or more STRTBL_CHUNK
# chunks. The hash key is the index value specified in STRTBL_CHUNK.
our %WrkStringTable = ();

# The following hash holds WRK file data specified by one or more MARKERS_CHUNK
# chunks. The hash key is the entry order occurance. (1, 2, ...)
our %WrkMarkers = ();

# The following hash holds WRK file data specified by one or more MEMRGN_CHUNK
# chunks. Unknown purpose. The hash key is the first byte (Id?) of the chunk.
our %MemRegionData = ();

# Key signature lookup hash. Hash key is the midi message value. Hash value is the
# corresponding music key signature.
our %KeySig = (-7 => 'Cb', -6 => 'Gb', -5 => 'Db', -4 => 'Ab', -3 => 'Eb', -2 => 'Bb',
               -1 => 'F', 0 => 'C', 1 => 'G', 2 => 'D', 3 => 'A', 4 => 'E', 5 => 'B',
               6 => 'F#', 7 => 'C#');

# The data in the following hash is used primarily by the Cakewalk program to remember 
# global user GUI related information. Refer to the &VarsChunk subroutine for details
# about hash keys and associated values.
our %CakeVars =();

# =====================================================================================
# WRK file extracted data for use when creating program output.
#
# The following hash holds the sysex bank data specified by the SYSEX_CHUNK 
# records in the WRK file data. The hash is loaded by &SysexChunk. The following 
# data is stored using the sysen bank number as the primary hash key.
#
#    bankNum => {'name' => text, 'auto' => bool, 'port' => int, 'sysex' => []}
#
our %SysexBank = ();

# The following hash holds the track related information including event data. A
# number of chunks contribute to this hash including: TRACK_CHUNK, NTRACK_CHUNK,
# TRKNAME_CHUNK, TRKBANK_CHUNK, NTRKOFS_CHUNK, TRKVOL_CHUNK, TRKPATCH_CHUNK, 
# TRKREPS_CHUNK, TRKOFFS_CHUNK, LYRIC_CHUNK
#
#    trackNum => {'name' => text, 'channel' => int, 'pitch' => int, 'velocity' => int,
#                 'port' => int, 'selected' => bool, 'muted' => bool, 'loop' => bool,
#                 'bank' => int, 'patch' => int, 'volume' => int, 'pan' => int,
#                 'offset' => int, 'repeat' => int, 'lyric' => bool, 'eventCnt' => 0,
#                 'events' => []}
#
our %TrackData = ();

# The following hash is used to process the WRK file data. The hash keys are the
# supported WRK file chunkId bytes (hex). Most of this data is used by the Cakewalk
# code for user program settings and operational functions and beyond the needs
# of this program. See qwrk.h and qwrk.cpp in the drumstick-2.11.0 code for more 
# information. The WRK file bytes associated with each chunkId are extracted to 
# $WrkData{'00'}{'chunkbytes'} before calling the chunk processor.
#
# The 'subr' subkey points to a chunk specific subroutine. This code parses the 
# chunk data and stores the result in the 'result' specified variable. This code is
# called by &ProcessWrkFile following chunk data extraction.
#
our %WrkData = (
   '00' => {'chunkbytes' => []},
   '01' => {'name' => 'TRACK_CHUNK', 'desc' => 'Track prefix',
            'subr' => \&TrackChunk, 'result' => \%TrackData},
   '02' => {'name' => 'STREAM_CHUNK', 'desc' => 'Events stream',   
            'subr' => \&StreamChunk, 'result' => \%TrackData},
   '03' => {'name' => 'VARS_CHUNK', 'desc' => 'Global variables',
            'subr' => \&VarsChunk, 'result' => \%CakeVars},
   '04' => {'name' => 'TEMPO_CHUNK', 'desc' => 'Tempo map', 
            'subr' => \&TempoChunk, 'result' => \%TempoData},
   '05' => {'name' => 'METER_CHUNK', 'desc' => 'Meter map',    
            'subr' => \&MeterChunk, 'result' => \%MeterData},
   '06' => {'name' => 'SYSEX_CHUNK', 'desc' => 'System exclusive bank', 
            'subr' => \&SysexChunk, 'result' => \%SysexBank},
   '07' => {'name' => 'MEMRGN_CHUNK', 'desc' => 'Memory region',
            'subr' => \&MemRegionChunk, 'result' => \%MemRegionData},
   '08' => {'name' => 'COMMENTS_CHUNK', 'desc' => 'Comments', 
            'subr' => \&VariableChunk, 'result' => \%WrkVariables},
   '09' => {'name' => 'TRKOFFS_CHUNK', 'desc' => 'Track offset',
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '0A' => {'name' => 'TIMEBASE_CHUNK', 'desc' => 'Timebase.',
            'subr' => \&TimebaseChunk, 'result' => \%WrkGlobal}, 
   '0B' => {'name' => 'TIMEFMT_CHUNK', 'desc' => 'SMPTE time format', 
            'subr' => \&TimeFmtChunk, 'result' => \%WrkGlobal}, 
   '0C' => {'name' => 'TRKREPS_CHUNK', 'desc' => 'Track repetitions',
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '0E' => {'name' => 'TRKPATCH_CHUNK', 'desc' => 'Track patch', 
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '0F' => {'name' => 'NTEMPO_CHUNK', 'desc' => 'New Tempo map',  
            'subr' => \&TempoChunk, 'result' => \%TempoData},
   '10' => {'name' => 'THRU_CHUNK', 'desc' => 'Extended thru parameters',
            'subr' => \&ThruChunk, 'result' => \%WrkGlobal}, 
   '12' => {'name' => 'LYRICS_CHUNK', 'desc' => 'Events stream with lyrics', 
            'subr' => \&StreamChunk, 'result' => \%TrackData},
   '13' => {'name' => 'TRKVOL_CHUNK', 'desc' => 'Track volume',   
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '14' => {'name' => 'SYSEX2_CHUNK', 'desc' => 'System exclusive bank',
            'subr' => \&SysexChunk, 'result' => \%SysexBank},
   '15' => {'name' => 'MARKERS_CHUNK', 'desc' => 'Markers',  
            'subr' => \&MarkersChunk, 'result' => \%WrkMarkers},
   '16' => {'name' => 'STRTAB_CHUNK', 'desc' => 'Table of text event types',   
            'subr' => \&StringTableChunk, 'result' => \%WrkStringTable},
   '17' => {'name' => 'METERKEY_CHUNK', 'desc' => 'Meter/Key map',
            'subr' => \&MeterChunk, 'result' => \%MeterData},
   '18' => {'name' => 'TRKNAME_CHUNK', 'desc' => 'Track name',  
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '1A' => {'name' => 'VARIABLE_CHUNK', 'desc' => 'Variable record chunk', 
            'subr' => \&VariableChunk, 'result' => \%WrkVariables},
   '1B' => {'name' => 'NTRKOFS_CHUNK', 'desc' => 'Track offset',
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '1E' => {'name' => 'TRKBANK_CHUNK', 'desc' => 'Track bank',
            'subr' => \&TrkMiscChunks, 'result' => \%TrackData},
   '24' => {'name' => 'NTRACK_CHUNK', 'desc' => 'Track prefix',
            'subr' => \&TrackChunk, 'result' => \%TrackData},   
   '2C' => {'name' => 'NSYSEX_CHUNK', 'desc' => 'System exclusive bank',
            'subr' => \&SysexChunk, 'result' => \%SysexBank},
   '2D' => {'name' => 'NSTREAM_CHUNK', 'desc' => 'Events stream',
            'subr' => \&StreamChunk, 'result' => \%TrackData},
   '31' => {'name' => 'SGMNT_CHUNK', 'desc' => 'Segment prefix',
            'subr' => \&StreamChunk, 'result' => \%TrackData},
   '4E' => {'name' => 'SOFTVER_CHUNK', 'desc' => 'Software version that saved file',
            'subr' => \&VarsChunk, 'result' => \%WrkGlobal},
   'FF' => {'name' => 'END_CHUNK', 'desc' => 'Last chunk, end of file'});

our $UsageText = (qq(
===== Help for $ExecutableName ================================================

GENERAL DESCRIPTION
   This program parses and extracts data from Cakewalk WRK file. This file
   type was used with early 90's versions of the Cakewalk MIDI Sequencer 
   program. Cakewalk MIDI sequencer WRK files hold sequencer related musical
   data (note, tempo, lyric, etc.), Cakewalk GUI settings, studio music 
   device configurations, and MIDI device system exclusive (sysex) data. 
   
   A Cakewalk feature of the sysex bank allows for marked sysex entries to be 
   auto-sent to the MIDI devices during sequence load. This feature was used 
   to initialize my pre-General Midi EMU Proteus units with the customized 
   presets needed for each sequence. In this way, each WRK file sequence is 
   standalone and does not rely on any previously used presets. A number of
   options are provided for processing this sysex data.
     
   The Cakewalk track/measure view provides user adjustment values. These
   settings alter MIDI event data during playback. This adjustment data, if 
   used, is stored in the WRK file. Playback start adjustments include pan,
   volume, and patch for each track. Dynamic adjustments during playback
   included MIDI note transposition, note velocity, and time offset. These
   adjustments are applied during MIDI output file creation unless the -n 
   option (no adjust) is specified.

   NOTE: This version of WrkFile2Mid uses the syxmidi tool for the -m, -M,
   and -s options. If these options are used, the syxmidi executable must
   be present in the WrkFile2Mid directory. See the syxmidi documentation.

   This program has been tested with Cakewalk WRK file versions 2.0, 3.0,
   and 'new 4.0'. New 4.0 identifies as 3.0 but has additional record types.
   The MIDI format 1 output file has been used with Audacity, Rosegarden, 
   and CLI pmidi (linuxmint) players. 
   
   In general, this CLI based program provides the following functions.
   
      1. Create a standard MIDI file of the musical sequence. This includes 
         all WRK file specified tracks unless limited by the -t option.  A 
         standard MIDI file <file>.mid is created from the input <file>.wrk.
         
      2. Optionally (-a) include MIDI device sysex data that is WRK file 
         marked as auto-send in track 0 of the MIDI file.  
         
      3. Optionally (-f) create a formatted sysex data file for use with this 
         program. WRK file specified auto-send, port, name, and raw sysex data 
         are included. The file <file>.sxd is created from the input <file>.wrk.
         
      4. Optionally (-e) create an export file containing the raw sysex data.
         This data can then be import/manipulated by an external program. The
         file <file>.syx is created from the input <file>.wrk.
      
      NOTE: New files silently overwrite any existing file of the same name.
   
   Support functions for the above are included.

      -s  Process the specified sysex file; .sxd or .syx. This option uses
          optional user input that is specified by the -p, -M and -z options. 
          Note that sysex data contains a manufacturer ID that must match 
          the target MIDI device to be successfully utilized. Otherwise, the
          device will ignore the sysex transmission. 
          
      -p  When the -p option is NOT specified, the processing of the .sxd or 
          .syx file occurs interactively with the user. The available MIDI 
          device ports are displayed for user selection. The devices displayed
          can be limited or ordered using the -M option. The available sysex 
          banks are then displayed for user selection and transmission.
          
          When the -p option value is numeric, the value represents the MIDI
          device port to use; e.g. 0, 1. The .sxd port value in each bank is 
          ignored. All .sxd sysex banks marked auto:yes are transmitted.
          
          When the -p option value is 'auto', the .sxd specified port value
          in each sysex bank is used. All .sxd sysex banks marked auto:yes 
          are transmitted. The -M option will likely be needed if more than 
          one MIDI device is available.
          
      -M  This option specifies one or more rawmidi port mappings. The first
          entry alters port 0, the second port 1, etc. Rawmidi ports are used 
          by the -s option and correspond to the .sxd file Port column value.
          The value entered for each port must wholly or partially match the
          Device or Name shown by the -m (lowercase) option. Examples:
          
          Port  Device       Name
           0    hw:2,0,0     MIDIPLUS TBOX 2x2 Midi In 1
           1    hw:2,0,1     MIDIPLUS TBOX 2x2 Midi In 2

             -M 'hw:2,0,1'  - Port 0 set to specified device.
             -M '0,1'       - Port 0 set to matching device hw:2,0,1.
             
          Semicolon separates multiple port mappings.
          
             -M 'In 2;In 1' - Port 0 set to device with name containing In 2.
                            - Port 1 set to device with name containing In 1.
             -M '0,1;In 1'  - Port 0 set to matching device hw:2,0,1.
                            - Port 1 set to device with name containing In 1.
          
      -z  Specifies a microsecond time delay value; typically 0-500. It is 
          used between bytes of the sysex data transmission associated with 
          the -s option. This throttle helps to mitigate data overload with 
          older MIDI devices. Default 250 if not specified.
       
      -t  Specifies the WRK file track(s) to process; multiple tracks must be
          comma separated. For example: -t 1,2,5 includes only tracks 1, 2, 
          and 5 in the standard MIDI file.
          
      -n  Disables use of WRK file specified track/measure adjustment values. 
          When not disabled, MIDI control events are added and note event data 
          is adjusted. Following WRK file to MIDI file conversion, a summary 
          of the adjustments performed will be displayed.

   Funtions of a diagnostic nature are also available.
   
      -c  Check the specified MIDI file by walking its header and track data
          structure. No other processing is performed.
      -m  Show available MIDI devices. 'Dir' lists the port supported MIDI 
          direction (Input and/or Output). 'Port', 'Device', and 'Name' show
          the device's details. No other processing is performed. 
      -u  Show unhandled chunk Ids that are present in the WRK file.
      -v  Display the WRK file chunk data after parsing. No other processing 
          is performed.
      -x  Displays a hex dump of the specified file. No other processing is 
          performed.

USAGE:
   $ExecutableName  [-h] [-d [<lvl>]] [-a] [-f] [-e <file>] [-s <file>.sxd] 
                   [-p <n>|auto] [-z <usec>] [-M <map>] [-t <trk>[,<trk]] [-m]
                   [-c <file>] [-n] [-u] [-v] [-x <file>] [<path>/]<file>

   -h            Displays program usage text.
   -d <lvl>      Run at specified debug level; 1-3. Higher number, more detail. 
                 Colored text is used for each level. Specify 'm' (e.g. 2m),
                 for monochrome text. Useful for redirected console output.

   -t <trk>      Process only the specified track(s).
   -a            Include sysex bank data in track 1 of MIDI file. 
   -f            Format sysex data to a -s useable .sxd file.
   -e            Export raw sysex data to a .syx file.
   
   -s <file>     Sysex data for transmission to a MIDI device.
   -p <p>|auto   MIDI device port. -s option interactive if not specified.
   -M <map>      Specifies a MIDI device port mapping string. 
   -z <usec>     Sysex throttle. Default 250 usec/byte.
    
   -c <file>     Check the specified file for valid MIDI format.
   -m            Show available MIDI devices.
   -n            Don't use WRK file track/measure adjustment values.
   -u            Show WRK file unknown chunkIds.
   -v            Display extracted WRK file data and then exit.
   -x <file>     Dump specified file as hex bytes.             
                 
EXAMPLES:

   $ExecutableName mySequence.wrk
      Process the specified cakewalk WRK file located in the current working
      directory. The file mySequence.mid is created. Sysex bank data is
      ignored.

   $ExecutableName -v mySequence.wrk
      Parse the specified cakewalk WRK file and display a summary of the
      data it contains. No output .mid file is created.

   $ExecutableName -a ./cakewalk/sequences/*.wrk
      Process all WRK files found in the cakewalk/sequences folder below the 
      current working directory. All corresponding .mid files are created in
      the specified directory and include auto-send sysex data in track 1.

   $ExecutableName -f mySequence.wrk
      Process the specified WRK file and create mySequence.sxd in the
      current working directory.

   $ExecutableName -p auto -M 'In 2;In 1' -s mySequence.sxd
      Transmit the auto:yes marked sysex banks in the mySequence.sxd file to
      a MIDI device(s). Use the .sxd specified port in each bank as mapped
      to a corresponding rawmidi device port.

VERSION: 
   $ExecutableName $Version
===============================================================================
));

# =============================================================================
# FUNCTION:  EncodeDeltaTime
#
# DESCRIPTION:
#    This routine is called to encode the specified numeric value to a MIDI
#    variable length value of up to four 7 bit bytes. The maximum value that
#    can be encoded is 2^28 -1 or 268,435,455. The bytes are returned in big
#    endian order.
#
#    Note: 'hex text bytes' are consistent with the internal MIDI data
#    representation used in this program.
#
# CALLING SYNTAX:
#    $result = &EncodeDeltaTime($Value);
#
# ARGUMENTS:
#    $Value          Value to be encoded.
#
# RETURNED VALUES:
#    1-4 bytes = Success,  () = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub EncodeDeltaTime {
   my ($Value) = @_;
   my @bytes = ();

   if ($Value > 0x0FFFFFFF) {          # 2^28 -1 = 268,435,455
      &ColorMessage("EncodeDeltaTime: invalid value $Value", "BRIGHT_RED", '');
   }
   else {
      unshift(@bytes, sprintf("%02X", ($Value & 0x7F)));   # Save LSB 7 bits.
      $Value = $Value >> 7;                   # Position to next 7 bit group.
      while ($Value > 0) {
         # Mask for bits 7-0 and set bit 8 to indicate another byte. 
         unshift(@bytes, sprintf("%02X", (($Value & 0x7F)) | 0x80));
         $Value = $Value >> 7;
      }
   }
   return @bytes;
}

# =============================================================================
# FUNCTION:  DecodeDeltaTime
#
# DESCRIPTION:
#    This routine is called to decode up to four 7 bit bytes of the specified 
#    MIDI variable length input to a numeric value. The input bytes must be
#    in big-endian order.
#
#    Note: 'hex text bytes' are consistent with the internal MIDI data
#    representation used in this program.
#
# CALLING SYNTAX:
#    $result = &DecodeDeltaTime(\@Bytes);
#
# ARGUMENTS:
#    $Bytes            Pointer to hex text bytes.
#
# RETURNED VALUES:
#    value = Success,  -1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub DecodeDeltaTime {
   my ($Bytes) = @_;
   my $value = 0;

   if ($#$Bytes > 3 or hex($$Bytes[-1]) > 127) {
      &ColorMessage("DecodeDeltaTime: invalid bytes @$Bytes", "BRIGHT_RED", '');
   }
   else {
      foreach my $byte (@$Bytes) {
         $value = $value << 7;
         $value += hex($byte) & 0x7F;
      }
   }
   return $value;
}

# =============================================================================
# FUNCTION:  SysexToTrack
#
# DESCRIPTION:
#    This routine is called to process the specified sysex data and store the
#    result in the specified output array. The time value is the time offset
#    for the initial F0 of the sysex bank. A 2 tick delay every 16 sysex bytes
#    is added to slow down the sysex data transmission. This helps to mitigate 
#    data overruns on the MIDI device.
#
#    The returned time value is the specified $SysexTime plus the number of
#    delay ticks used by the sysex data. This facilitates subsequent sysex
#    bank processing by the caller. System exclusive messages are F0..F7
#    delimited and must not overlap in their transmission time on the same
#    MIDI port.
#
# CALLING SYNTAX:
#    $time = &SysexToTrack(\%WrkGlobal, \@ArrayPnt, \@SysexData, $SysexTime);
#
# ARGUMENTS:
#    $WrkGlobal        Pointer to %WrkGlobal hash.
#    $ArrayPnt         Pointer to output array.
#    $SysexData        Pointer to sysex data array.
#    $SysexTime        Time offset for 1st group. 
#
# RETURNED VALUES:
#    <num> = Success,  -1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub SysexToTrack {
   my ($WrkGlobal, $ArrayPnt, $SysexData, $SysexTime) = @_;
   my $deltaTime = $SysexTime;   # Initial deltaTime value.
   my $elapseTime = $deltaTime;
   my $delayTicks = 2;
   &DisplayDebug(1,"SysexToTrack: SysexTime: $SysexTime   delayTicks: $delayTicks");
   &DisplayDebug(2,"SysexToTrack: @$SysexData");

   # Each F0 is followed by a length up to and including the F7. Loop until all
   # F0..F7 groups are processed.
   while (scalar @$SysexData > 0) {       
      my @syx = ();
      # Get a sysex group into @syx.
      for (my $x = 0; $x <= $#$SysexData; $x++) {
         if ($$SysexData[$x] eq 'F7') {
            @syx = splice(@$SysexData, 0, $x +1);
            last;
         }
         elsif ($x == $#$SysexData) {
            &ColorMessage("SysexToTrack: invalid sysex, no F7: @$SysexData",
                          "BRIGHT_RED", '');
            return -1;
         }
      }
      last if (scalar @syx == 0);   # All F0 .. F7 entries processed.
         
      # Create sysex record and add it to the output array. The sysex is broken up
      # into 16 byte chunks to facilitate transmission throttling via $delayTicks.
      splice(@syx, 0, 1);           # Remove F0 for length calc.
      my @syxRec = &EncodeDeltaTime($deltaTime);
      push (@syxRec, 'F0');
      while (scalar @syx > 16) {
         my @bytes = splice(@syx, 0, 16);
         &DisplayDebug(2,"SysexToTrack: --> @bytes");
         push(@syxRec, &EncodeDeltaTime(scalar @bytes), @bytes);
         push(@syxRec, &EncodeDeltaTime($delayTicks), 'F7'); # sysex continue
         $elapseTime += $delayTicks;
      }
      &DisplayDebug(2,"SysexToTrack: --> @syx");
      push(@syxRec, &EncodeDeltaTime(scalar @syx), @syx);
      &DisplayDebug(2,"SysexToTrack: @syxRec");
      push (@$ArrayPnt, @syxRec);
      $deltaTime = $delayTicks;    # Subsequent F0..F7 deltaTime value.
      $elapseTime += $delayTicks;
   }
   return $elapseTime;
}

# =============================================================================
# FUNCTION:  ProcessNoteOff
#
# DESCRIPTION:
#    This routine is called to process the %noteOff hash. This hash holds entries
#    for note-off events. An entry is created by &ProcessEvents for each note-on 
#    (9x) event. The note-off time value is the hash key and is computed based on
#    the note-on time position and note duration. The hash value is the note status
#    byte and note's keyboard value; e.g. 90:43. Multiple notes that share an off
#    time are comma separated; e.g. 90:43,90:4D.
#
#    MIDI running status methodology is used for repeating events to minimize the
#    MIDI data stream.
#
# CALLING SYNTAX:
#    $result = &ProcessNoteOff(\@ArrayPnt, \%NoteOff, \$LastTime, \$LastEvent,
#                              \$TimeLimit);
#
# ARGUMENTS:
#    $ArrayPnt         Pointer to output array.
#    $NoteOff          Pointer to %NoteOff hash.
#    $LastTime         Pointer to last event time.
#    $LastEvent        Pointer to last event.
#    $TimeLimit        Limit processing time value.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ProcessNoteOff {
   my ($ArrayPnt, $NoteOff, $LastTime, $LastEvent, $TimeLimit) = @_;
   
   foreach my $offTime (sort {$a <=> $b} keys(%$NoteOff)) {
      if ($TimeLimit >= 0 ) {
         last if ($offTime > $TimeLimit);   # Up to and including TimeLimit time.
      }
      my @notesOff = split(',', $$NoteOff{$offTime}); # Possible shared off time.
      foreach my $noteEvent (@notesOff) {
         my ($event, $note) = split(':', $noteEvent);
         my $deltaTime = $offTime - $$LastTime;
         my @nOff = &EncodeDeltaTime($deltaTime);               # Time
         push (@nOff, $event) if ($event ne $$LastEvent);       # Event
         push (@nOff, $note, '00');              # Note key and velocity 0
         &DisplayDebug(3,"  NoteOff: @nOff  offTime: $offTime  eventTime: $TimeLimit");
         push (@$ArrayPnt, @nOff);
         $$LastTime = $offTime;
         $$LastEvent = $event;
      }
      delete $$NoteOff{$offTime};                 # Remove processed note-off.
   }
   return 0;
}

# =============================================================================
# FUNCTION:  ProcessEvents
#
# DESCRIPTION:
#    Called to process the event data for the specified track Id. This event
#    data was stored in $TrackData in its WRK file form as shown. The three 
#    time value bytes are converted to a MIDI delta-time since previous event.
#    The status byte specifies how the bytes that follow it are interpreted.
#
#    MIDI note data are further processed since WRK file track parameters can
#    be used to adjust the values of timing, pitch, and velocity. 
#
#    MIDI running status methodology is used for repeating events to minimize
#    the MIDI data stream.
#
#    Event data: %TrackData{$trackNum}{'events'}
#       time: int24         <- three byte little endian
#       status: int8        <- one byte     upper nibble = type
#                                           lower nibble = midi channel
#       data1: int8         <- one byte, 7 bits  e.g. note value     0-127
#       data2: int8         <- one byte, 7 bits  e.g. note velocity  0-127
#       duration: int16     <- two bytes little endian
#
#    Example MIDI track output.
#       4D 54 72 6B 00 00 09 94       MTrk
#       00 FF 58 04 04 02 18 08       time signature
#       00 FF 59 02 00 00             key signature
#       00 FF 51 03 05 B8 D8          set tempo
#       00 FF 2F 00                   end of track
#       4D 54 72 6B 00 00 09 94       MTrk
#       00 FF 21 01 00                send to midi port 0 (deprecated)
#       00 FF 03 0A 50 69 7A 7A 20 43 65 6C 6C 69    track name
#       00 C0 2D        patch 45
#       00 B0 07 73     volume  115 (track view setting?)
#       00    0A 3C     pan 60
#       00    07 73     volume 115 again (track event?)
#       83 5C 90 24 55  1st note @ time 480 (measure 1:0)
#       1D       24 00  note vel 0 @ 1D later (16th note)
#       5B       2B 50  2nd note 5B after previous off 
#       1D       2B 00  note vel 0 @ 1D later (16th note)
#       5B       28 4B  3rd note 5B after previous off 
#       1D       28 00  ...
#       
# CALLING SYNTAX:
#    $result = &ProcessEvents($ArrayPnt, $TrackData, $Id, $WrkGlobal, $Adjust, $Lyric);
#
# ARGUMENTS:
#    $ArrayPnt         Pointer to output array.
#    $TrackData        Pointer to track data hash.
#    $Id               Track to process.
#    $WrkGlobal        Pointer to %WrkGlobal.
#    $Adjust           'yes' or 'no'. Apply WRK adjustment values.
#    $Lyric            'yes' or 'no'. Track contains lyrics.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None
# =============================================================================
sub ProcessEvents {
   my ($ArrayPnt, $TrackData, $Id, $WrkGlobal, $Adjust, $Lyric) = @_;
   my ($eventCnt, $lastTime, $lastEvent, $offAt) = (0,0,0,0);
   my ($eventTime, $event, $channel, $type, @data, $lyricLen, @lyricText);
   my %noteOff = ();                # See &ProcessNoteOff for hash description.
  
   $eventCnt = $$TrackData{$Id}{'eventCnt'} if (exists($$TrackData{$Id}{'eventCnt'}));
   &DisplayDebug(1,"ProcessEvents: track: $Id   eventCnt: $eventCnt   Adjust: $Adjust   " .
                   "Lyric: $Lyric   WRK ver: $$WrkGlobal{'version'}");
   return 0 if ($eventCnt == 0);
   
   my @eventBytes = @{ $$TrackData{$Id}{'events'} };
   my $trackEventCount = scalar @eventBytes;
   &DisplayDebug(2,"ProcessEvents: eventBytes: @eventBytes");
   while (scalar @eventBytes > 0) {
      my @time = splice(@eventBytes, 0, 3);               # Assemble time bytes 
      $eventTime = (hex($time[2]) << 16) + (hex($time[1]) << 8) + hex($time[0]);
      $event = splice(@eventBytes, 0, 1);                 # Event byte
      $type = substr($event, 0, 1);                       # Isolate type.
      $channel = $$TrackData{$Id}{'channel'} & 0x0F;      # Get channel nibble.
      $event = join('', $type, sprintf("%1X", $channel)); # Add channel to event
      $type = join('', $type, '0');                       # Normalize type.
      &DisplayDebug(3,"eventTime: $eventTime (@time)   channel: $channel   " .
                      "event: $event   type: $type");

      # ------------------------------------------------------------------------
      # Get the data bytes associated with the event.
      if ($type ge '80' and $type lt 'F0') {
         $offAt = 0;                                      # For debug below
         @data = splice(@eventBytes, 0, 1);               # Event data1 byte
         if ($$WrkGlobal{'version'} eq "3.0" or $Lyric eq 'yes') {
            if ($type ne 'C0' and $type ne 'D0') {
               push (@data, splice(@eventBytes, 0, 1));   # Event data2 byte
            }
         }
         elsif ($$WrkGlobal{'version'} eq "2.0") {
            if ($type eq 'C0' or $type eq 'D0') {
               splice(@eventBytes, 0, 1);                 # Discard WRK MSB of data1. 
               splice(@eventBytes, 0, 2);                 # Discard unused data2.
            }
            elsif ($type ne 'F0') {
               push (@data, splice(@eventBytes, 0, 1));   # Event data2 byte
               if ($type ne '80' and $type ne '90') {
                  splice(@eventBytes, 0, 2);              # Discard unused duration bytes.
               }
            }
         }
         else {
            &ColorMessage("ProcessEvents: unhandled WRK file verion: $$WrkGlobal{'version'}",
                          "BRIGHT_YELLOW", '');
         }
         &DisplayDebug(3,"eventTime: $eventTime (@time)   event: $event   data: @data");

         # Adjust timing if specified by a cakewalk track view setting.
         if ($Adjust eq 'yes' and defined($$TrackData{$Id}{'offset'})) {
            my $adj = $$TrackData{$Id}{'offset'};
            $adj = $adj - 0xFFFFFFFF -1 if ($adj > 65535);  # negative
            $eventTime = ($eventTime + $adj) >= 0 ? $eventTime += $adj : $eventTime;
            &DisplayDebug(3,"eventTime adjusted: $eventTime   event: $event   adj: $adj");
         }

         if ($type eq '90') {                             # Note-on processing.
            # @data[0] = note, @data[1] = velocity
            my @dur = splice(@eventBytes, 0, 2);          # 2 duration bytes.
            my $noteDur = (hex($dur[1]) << 8) + hex($dur[0]);
            &DisplayDebug(3,"eventTime: $eventTime (@time)   event: $event   dur: @dur");
            
            # Adjust pitch if specified by a cakewalk track view setting.
            if ($Adjust eq 'yes' and $Lyric eq 'no' and defined($$TrackData{$Id}{'pitch'})) { 
               my $adj = $$TrackData{$Id}{'pitch'} & 0xFF;
               $adj = $adj - 256 if ($adj > 127);         # If a negative adjust
               my $newPitch = hex($data[0]) + $adj;       # Compute new pitch.
               $newPitch += 12 while ($newPitch < 0);     # Per cakewalk user guide
               $newPitch -= 12 while ($newPitch > 127);   # Per cakewalk user guide
               $data[0] = sprintf("%02X", $newPitch);     # Set new value
            }

            # Adjust velocity if specified by a cakewalk track view setting.
            if ($Adjust eq 'yes' and $Lyric eq 'no' and defined($$TrackData{$Id}{'velocity'})) {
               my $adj = $$TrackData{$Id}{'velocity'} & 0xFF;
               $adj = $adj - 256 if ($adj > 127);         # If a negative adjust
               my $newVel = hex($data[1]) + $adj;         # Compute new velocity.
               $newVel = 1 if ($newVel < 1);
               $newVel = 127 if ($newVel > 127);
               $data[1] = sprintf("%02X", $newVel);       # Set new value
            }
            
            # Add future note-off event.
            my $offTime = $eventTime + $noteDur;
            if (exists( $noteOff{$offTime} )) {
               $noteOff{$offTime} = join(',', $noteOff{$offTime}, # Add note-off.
                                    join(':', $event, $data[0])); 
            }
            else {
               $noteOff{$offTime} = join(':', $event, $data[0]);  # Set note-off.
            }
            $offAt = $offTime;      # For debug message below.
         }
      }
      elsif ($type eq 'F0') {                # System Common Messages
         next if ($event eq 'F4' or $event eq 'F5');  # Ignore undefined events.
         if ($event eq 'F0') {                        # F0 sysex data
            # Get the embedded sysex data. Error if no F7 found.
            for (my $y = 0; $y <= $#eventBytes; $y++) {
               if ($eventBytes[$y] eq 'F7') {
                  @data = splice(@eventBytes, 0, $y +1);
                  unshift (@data, $event);   # Include F0 for &SysexToTrack below
                  last;
               }
            }
            unless (scalar @data > 0) {
               &ColorMessage("ProcessEvents: invalid sysex. No F7: @eventBytes",
                             "BRIGHT_RED", '');
               return 1;
            }
         }
         elsif ($event ge 'F1' and $event le 'F3') {  # Time code thru Song select 
            @data = splice(@eventBytes, 0, 1);
            # Second byte of song position pointer.
            push (@data, splice(@eventBytes, 0, 1)) if ($event eq 'F2');
         }
         else {
            @data = ();                               # No message bytes.
         }
      }
      elsif ($Lyric eq 'yes' and $event eq '02') {
         my @lenBytes = splice(@eventBytes, 0, 4);
         $lyricLen = hex($lenBytes[3])*16777216 + hex($lenBytes[2])*65536 + 
                     hex($lenBytes[1])*256 + hex($lenBytes[0]);
         @lyricText = splice(@eventBytes, 0, $lyricLen);
      }
      else {
         my $offset = $trackEventCount - (scalar @eventBytes);
         &ColorMessage("ProcessEvents: unknown event: '$event' at: $offset  " .
                       "@eventBytes", "BRIGHT_RED", '');
         return 1;
      }
      
      # ------------------------------------------------------------------------
      # Add note-off events to output array for times <= $eventTime.
      return 1 if (&ProcessNoteOff($ArrayPnt, \%noteOff, \$lastTime, \$lastEvent, 
                                   $eventTime));

      # ------------------------------------------------------------------------
      # Add the MIDI event to the output array. If the computed delta time is
      # negative, then the eventTime value is used directly. In this case, MIDI
      # running status is reset.
      my $deltaTime = $eventTime - $lastTime;
      if ($deltaTime < 0) {
         $deltaTime = $eventTime;
         $lastEvent = '';
      }
      my @evnt = ();
      if ($event eq 'F0') {                                 # F0 sysex data ?
         $eventTime = &SysexToTrack($WrkGlobal, \@evnt, \@data, $deltaTime);
      }
      else {
         @evnt = &EncodeDeltaTime($deltaTime);              # Time
         if ($event eq '02') {                              # Add lyric meta-data?
            push (@evnt, 'FF','05', sprintf("%02X", $lyricLen), @lyricText);
            $lastEvent = '';
         }
         else {
            push (@evnt, $event) if ($event ne $lastEvent); # Event
            push (@evnt, @data);                            # Event data
         }
      }
      
      # Note: Displayed @evnt will not include the event byte if same as previous.
      # This is per MIDI spec for 'Running Status'.
      &DisplayDebug(3,"   Event: @evnt   eventTime: $eventTime   event: $event" .
                      "   lastEvent: $lastEvent   lastTime: $lastTime" .
                      "   offAt: $offAt");
      push (@$ArrayPnt, @evnt);
      $lastTime = $eventTime;
      $lastEvent = $event;

      # ------------------------------------------------------------------------
      # If data remains in @eventBytes, there should always be at least 4 bytes, 
      # 3 for time and 1 for event. Otherwise we're lost.
      if (scalar @eventBytes != 0 and scalar @eventBytes < 4) {
         &ColorMessage("ProcessEvents: invalid remaining data: @eventBytes",
                       "BRIGHT_RED", '');
         &DisplayDebug(1,"ProcessEvents data: @$ArrayPnt");
         return 1;
      }
   }
   
   # All track events have been processed. Drain the %noteOff hash.
   return 1 if (&ProcessNoteOff($ArrayPnt, \%noteOff, \$lastTime, \$lastEvent, -1));
   
   return 0;
}

# =============================================================================
# FUNCTION: MidiFileHeader
#
# DESCRIPTION:
#    This routine adds MIDI file header data to the specified array. Delta-time
#    0 is used for these data. The -a option causes the $AddSyx input to be set
#    to 'yes'. This results in the auto-send indicated sysex data to be included
#    in the first track.
#
#    Midi file header: 
#       'MThd'         <- four ascii bytes
#       length: int32  <- four bytes big endian
#       format: int16  <- two bytes big endian; 0000=mf0, 0001=mf1, 0002=mf2
#       trkCnt: int16  <- two bytes big endian
#       bpqn: int16    <- two bytes big endian; beats per quarter note
#
#    Midi track header: 
#       'MTrk'         <- four ascii bytes
#       length: int32  <- four bytes big endian
#       int8 ...       <- data bytes
#       eot: int8      <- three required end of track bytes 
#
# CALLING SYNTAX:
#    $result = &MidiFileHeader($ArrayPnt, $SysexBank, $TempoData, $MeterData, 
#                              $WrkGlobal, $TrkCount, $File, $AddSyx);
#
# ARGUMENTS:
#    $ArrayPnt         Pointer to output array.
#    $SysexBank        Pointer to %SysexBank hash.
#    $TempoData        Pointer to %TempoData hash.
#    $MeterData        Pointer to %MeterData hash.
#    $WrkGlobal        Pointer to WRK global data hash.
#    $TrkCount         Track count.
#    $File             File name to create.
#    $AddSyx           'yes' or 'no'. Add sysex to header when 'yes'.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub MidiFileHeader {
   my ($ArrayPnt, $SysexBank, $TempoData, $MeterData, $WrkGlobal, $TrkCount, $File,
       $AddSyx) = @_;
   my $bpm = 120;                # Default beats per minute.
   my ($keySig) = 0;             # Default key of C.
   my ($num, $dem) = (4, 4);     # Default 4/4 time signature.
   my %pwr2 = (1=>'00',2=>'01',4=>'02',8=>'03',16=>'04',32=>'05',64=>'06');
   my ($smpteFrame, $smpteOffset) = (0,0);
   my ($measure);
   &DisplayDebug(1,"MidiFileHeader: AddSyx: '$AddSyx'  TrkCount: $TrkCount  $File ...");

   # Build the MIDI file header.
   @$ArrayPnt = ('4D','54','68','64','00','00','00','06');
   push (@$ArrayPnt, '00', '01');   # midi file format 1
   my $cnt = $TrkCount + 1;         # Add 1 for MIDI meta-data track
   push (@$ArrayPnt, sprintf("%02X", $cnt/256), sprintf("%02X", $cnt&255));
   $bpm = $$WrkGlobal{'timebase'} if (exists($$WrkGlobal{'timebase'}));
   push (@$ArrayPnt, sprintf("%02X", $bpm/256), sprintf("%02X", $bpm&255));
   &DisplayDebug(1,"MidiFileHeader: Hdr: @$ArrayPnt");

   # The first track holds the MIDI file meta-data. It also includes the sysex data
   # if -a is specified.
   my @trk = ('4D','54','72','6B','00','00','00','00');
   
   # Add sysex to header track if user specified.
   if ($AddSyx eq 'yes') {
      my ($eTime, $eInc) = (0,5);
      foreach my $key (sort {$a <=> $b} keys(%$SysexBank)) {
         if ($$SysexBank{$key}{'auto'} == 1) {
            my @sysexData = @{ $$SysexBank{$key}{'sysex'} };
            $eTime = &SysexToTrack($WrkGlobal, \@trk, \@sysexData, $eTime);
            return 1 if ($eTime < 0);
            $eTime += $eInc;
         }
      }
   }

   # File name.
   my @name = map { sprintf '%02X', ord } split //, $File;
   my $nameLen = scalar @name;
   push (@trk, '01','FF','03', sprintf("%02X", $nameLen), @name);
   my @nameRec = @trk[$#trk-($nameLen-1) .. $#trk];   
   &DisplayDebug(1,"MidiFileHeader: name rec: @nameRec   " . pack("(H2)*", @nameRec));
   
   # Time signature.
   my @meterKeyList = sort {$a <=> $b} keys(%$MeterData);
   if (scalar @meterKeyList > 0 ) {
      $measure = $meterKeyList[0];              # Get 1st entry index.
      my @data = split(':', $$MeterData{ $measure });    
      $num = $data[0];   $dem = $data[1];
      $keySig = $data[2] if (defined($data[2]));
   }
   push (@trk, '01','FF','58','04', sprintf("%02X", $num), $pwr2{$dem}, '18','08');
   my @meterRec = @trk[$#trk-7 .. $#trk];   
   &DisplayDebug(1,"MidiFileHeader: meter rec: @meterRec");
   
   # Musical key. No major/minor designation from WRK file so always major.
   push (@trk, '01','FF','59','02', sprintf("%02X", $keySig), '00');
   my @keyRec = @trk[$#trk-5 .. $#trk];   
   &DisplayDebug(1,"MidiFileHeader: key rec: @keyRec");

   # SMPTE if specified. FF 54 05 hr mn se fr ff  audio, fr is samples
   if ($smpteFrame > 0) {
      my %hrs = (24 => '00', 25 => '20', 29 => '40', 30 => '60');
      $smpteFrame = 24 unless (exists($hrs{$smpteFrame}));  # Default 24 fps.
      push (@trk, '01','FF','54','05', $hrs{$smpteFrame}, '00','00','00','00');
      my @smpteRec = @trk[$#trk-8 .. $#trk];   
      &DisplayDebug(1,"MidiFileHeader: smpte rec: @smpteRec");
   }
      
   # Add tempo meta-event(s). Add a default tempo if none. Note tempo value
   # 16000 = 160.00 bpm, 12325 = 123.25 bpm
   $$TempoData{0} = $bpm * 100 if (scalar keys(%$TempoData) == 0);
   my @tempos = sort {$a <=> $b} keys(%$TempoData);
   &DisplayDebug(1,"MidiFileHeader: tempos: @tempos");
   foreach my $time (@tempos) {
      my @tempoRec = &EncodeDeltaTime($time);
      push (@tempoRec, 'FF','51','03');
      my $tempo = $$TempoData{$time}/100;
      my $uSecQnote = 60000000 / $tempo;
      push (@tempoRec, sprintf("%02X", ($uSecQnote >> 16) & 0xFF), 
                       sprintf("%02X", ($uSecQnote >> 8) & 0xFF), 
                       sprintf("%02X", ($uSecQnote & 0xFF)));
      &DisplayDebug(1,"MidiFileHeader: tempo rec: @tempoRec ($time - $tempo bpm)");
      push (@trk, @tempoRec);
   }

   # Add end-of-track and set final track record length.
   push (@trk, '01','FF','2F','00');

   my $trkLen = scalar @trk -8;   
   splice(@trk,4,4, sprintf("%02X", $trkLen/16777216), sprintf("%02X", $trkLen/65536), 
          sprintf("%02X", $trkLen/256), sprintf("%02X", $trkLen&255));
   &DisplayDebug(1,"MidiFileHeader: trk: @trk");

   push (@$ArrayPnt, @trk);
   return 0;
}

# =============================================================================
# FUNCTION: CreateSysexFile
#
# DESCRIPTION:
#    This routine writes the extracted sysex data to a file. WRK file extracted 
#    data is stored in the %SysexBank hash. The output file extension (.sxd or 
#    .syx) specifies the type of file to create. A .sxd file is formatted for use
#    with the -s option. The .syx file contains the raw unformatted sysex bytes.
#
#    bankNum => {'name' => text, 'auto' => bool, 'port' => int, 'sysex' => []}
#
# CALLING SYNTAX:
#    $result = &CreateSysexFile($SysexBank, $BankList, $Path, $File);
#
# ARGUMENTS:
#    $SysexBank        Pointer to %SysexBank hash.
#    $BankList         Comman separated bank numbers to include.
#    $Path             Directory path for file.
#    $File             File name to create. Also needed in MIDI header.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub CreateSysexFile {
   my ($SysexBank, $BankList, $Path, $File) = @_;
   my ($auto, $port, $name);
   
   &DisplayDebug(1,"CreateSysexFile $Path/$File ...");
   my @sysexTrks = sort {$a <=> $b} keys(%$SysexBank);     # Default all banks.
   @sysexTrks =  split(',', $BankList) if ($BankList ne '');
   my @sysexData = ();
   
   # Step through %SysexBank hash.
   foreach my $key (@sysexTrks) {
      next unless ( exists($$SysexBank{$key}) );     # Invalid sysex bank number.
      my @sysex = @{ $$SysexBank{$key}{'sysex'} };
      next if (scalar @sysex == 0);                  # No sysex data.
      if ($File =~ m/syx$/i) {                       # Raw sysex data to file? 
         push (@sysexData, @sysex);
         &DisplayDebug(2,"CreateSysexFile: syx: @sysex");
      }
      else {
         $auto = 'no';
         if (defined($$SysexBank{$key}{'auto'})) {
             $auto = $$SysexBank{$key}{'auto'} ? 'yes' : 'no';
         }
         push (@sysexData, "auto:$auto"); 
         $port = defined($$SysexBank{$key}{'port'}) ? $$SysexBank{$key}{'port'} : 0; 
         push (@sysexData, "port:$port");
         $name = defined($$SysexBank{$key}{'name'}) ? $$SysexBank{$key}{'name'} : '<none>'; 
         $name = '<none>' if ($name eq '');
         push (@sysexData, "name:$name");
         push (@sysexData, "sysx:" . join('', @sysex));
         my @sysexRec = @sysexData[$#sysexData-3 .. $#sysexData];
         foreach my $rec (@sysexRec) {
            &DisplayDebug(2,"CreateSysexFile: sxd: $rec");
         }  
      }
   }

   # Write @sysexData to file.
   if (scalar @sysexData > 0) {
      my $pathFile = join('', $Path, $File); 
      if ($File =~ m/syx$/i) {  
         return 1 if (&WriteData($pathFile, \@sysexData));  # Write binary
      } 
      else {
         return 1 if (&WriteFile($pathFile, \@sysexData, ''));
      }
      &ColorMessage("Sysex file created: $pathFile", "WHITE", '');
   }
   return 0;
}

# =============================================================================
# FUNCTION: CreateMidiFile
#
# DESCRIPTION:
#    This routine writes the extracted track data to a MIDI file. WRK file
#    extracted data is stored in the %TrackData hash. Each tracks event data
#    will be in a separate MIDI file track.
#
#    $TrackList specifies a comma separated list of tracks to process. Note
#    track numbers start at 0 as key sorted in the %TrackData hash.
#
# CALLING SYNTAX:
#    $result = &CreateSysexFile($TrackData, $SysexBank, $TempoData, $MeterData,
#                 $WrkGlobal, $TrackList, $Path, $File, $AddSyx, $Adjust);
# ARGUMENTS:
#    $TrackData        Pointer to %TrackData hash.
#    $SysexBank        Pointer to %SysexBank hash.
#    $TempoData        Pointer to %TempoData hash.
#    $MeterData        Pointer to %MeterData hash.
#    $WrkGlobal        Pointer to WRK global data hash.
#    $TrackList        Comman separated tracks numbers to include.
#    $Path             Directory path for file.
#    $File             File name to create. Also needed in MIDI header.
#    $AddSyx           'yes' or 'no'. Used by &MidiFileHeader.
#    $Adjust           'yes' or 'no'. Apply WRK adjustment values.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub CreateMidiFile {
   my ($TrackData, $SysexBank, $TempoData, $MeterData, $WrkGlobal, $TrackList, 
       $Path, $File, $AddSyx, $Adjust) = @_;
   my ($midiChannel, $midiPort) = (0,0);
   
   &DisplayDebug(1,"CreateMidiFile TrkList: '$TrackList'  $Path$File ...");
   my (@doTracks) = split(',', $TrackList);
   return 0 if (scalar @doTracks == 0);
   my (@midiData) = ();
   
   # Add MIDI file header data to array.
   return 1 if (&MidiFileHeader(\@midiData, $SysexBank, $TempoData, $MeterData,
                                $WrkGlobal, scalar @doTracks, $File, $AddSyx));
   # Process track events.
   foreach my $key (@doTracks) {
      if (exists($$TrackData{$key})) {      
         # Track header and length bytes.
         my @trk = ('4D','54','72','6B','00','00','00','00');

         # Track meta-data; MIDI channel.
         if (defined($$TrackData{$key}{'channel'})) {
            $midiChannel = $$TrackData{$key}{'channel'};
            if ($midiChannel >= 0 and $midiChannel < 16) {    
               push (@trk, '00','FF','20','01', sprintf("%02X", $midiChannel));
               my @chanRec = @trk[$#trk-4 .. $#trk];   
               &DisplayDebug(1,"CreateMidiFile track $key midiChannel: $midiChannel" .
                               "   @chanRec");
            }
            else {
               &DisplayDebug(1,"CreateMidiFile --> ignored trackview channel value: " .
                              $$TrackData{$key}{'channel'});
            }
         }
         # Track meta-data; name.
         if (defined($$TrackData{$key}{'name'})) {
            my @name = map { sprintf '%02X', ord } split //, $$TrackData{$key}{'name'};
            my $nameLen = scalar @name;
            push (@trk, '00','FF','03', sprintf("%02X", $nameLen), @name);
            my @nameRec = @trk[$#trk-($nameLen-1) .. $#trk];   
            &DisplayDebug(1,"CreateMidiFile track $key name: @nameRec   " . 
                          pack("(H2)*", @nameRec));
         }
         # Add device port. (deprecated meta event)
         if (defined($$TrackData{$key}{'port'})) {
            if ($$TrackData{$key}{'port'} >= 0 and $$TrackData{$key}{'port'} < 128) {
               push (@trk, '00','FF','21','01', sprintf("%02X", $$TrackData{$key}{'port'}));
               my @portRec = @trk[$#trk-4 .. $#trk];   
               &DisplayDebug(1,"CreateMidiFile track $key midiPort: " .
                               "$$TrackData{$key}{'port'}   @portRec");
            }
            else {
               &DisplayDebug(1,"CreateMidiFile --> ignored trackview port value: " .
                               $$TrackData{$key}{'port'});
            }
         }
         # Add events for Cakewalk track view specified values unless user disabled. 
         # The midiChannel value is included in the status byte. Don't add if value 
         # is out of range.
         if ($Adjust eq 'yes' and defined($$TrackData{$key}{'patch'})) {   # C0
            if ($$TrackData{$key}{'patch'} >= 0 and $$TrackData{$key}{'patch'} < 128) { 
               my $statusByte = 0xC0 + $midiChannel;  
               push (@trk, '00', sprintf("%02X", $statusByte), 
                                 sprintf("%02X", $$TrackData{$key}{'patch'}));
               my @patchRec = @trk[$#trk-2 .. $#trk];   
               &DisplayDebug(1,"CreateMidiFile track $key patch: @patchRec");
            }
            else {
               &DisplayDebug(1,"CreateMidiFile --> ignored trackview patch value: " .
                              $$TrackData{$key}{'patch'});
            }
         }
         if ($Adjust eq 'yes' and defined($$TrackData{$key}{'volume'})) {  # B0 07
            if ($$TrackData{$key}{'volume'} >= 0 and 
                $$TrackData{$key}{'volume'} < 128) { 
               my $statusByte = 0xB0 + $midiChannel;
               push (@trk, '00', sprintf("%02X", $statusByte), '07', 
                                 sprintf("%02X", $$TrackData{$key}{'volume'}));
               my @volRec = @trk[$#trk-3 .. $#trk];   
               &DisplayDebug(1,"CreateMidiFile track $key volume: @volRec");
            }
            else {
               &DisplayDebug(1,"CreateMidiFile --> ignored trackview volume value: " .
                              $$TrackData{$key}{'volume'});
            }
         }
         if ($Adjust eq 'yes' and defined($$TrackData{$key}{'pan'})) {     # B0 0A
            if ($$TrackData{$key}{'pan'} >= 0 and $$TrackData{$key}{'pan'} < 128) { 
               my $statusByte = 0xB0 + $midiChannel;
               push (@trk, '00', sprintf("%02X", $statusByte), '0A', 
                                 sprintf("%02X", $$TrackData{$key}{'pan'}));
               my @panRec = @trk[$#trk-3 .. $#trk];   
               &DisplayDebug(1,"CreateMidiFile track $key pan: @panRec");
            }
            else {
               &DisplayDebug(1,"CreateMidiFile --> ignored trackview pan value: " .
                               $$TrackData{$key}{'pan'});
            }
         }
         # Add event data to the track and set its length.
         my $lyric = defined($$TrackData{$key}{'lyric'}) ? 'yes' : 'no';
         return 1 if (&ProcessEvents(\@trk, $TrackData, $key, $WrkGlobal, $Adjust, 
                                     $lyric)); 
         push (@trk, '00','FF','2F','00');   # End-of-track marker
         my @eotRec = @trk[$#trk-3 .. $#trk];   
         &DisplayDebug(1,"CreateMidiFile track $key eot: @eotRec");
   
         my $trkLen = scalar @trk -8;
         splice(@trk,4,4, sprintf("%02X", $trkLen/16777216), 
            sprintf("%02X", $trkLen/65536), sprintf("%02X", $trkLen/256),
            sprintf("%02X", $trkLen&255));
         push (@midiData, @trk);
      }
      else {
         &ColorMessage("Invalid TrackData hash key: $key", "BRIGHT_RED", '');
      }
   }
      
   # Write @midiData to file.
   if (scalar @midiData > 0) {
      my $pathFile = join('', $Path, $File);   
      return 1 if (&WriteData($pathFile, \@midiData));
      &ColorMessage("MIDI file created:  $pathFile", "WHITE", '');
   }
   return 0;
}

# =============================================================================
# FUNCTION: ProcessWrkFile
#
# DESCRIPTION:
#    This routine walks the specified Cakewalk WRK file data. The data contains
#    chunk identifiers for the various records. The bytes for each chunk are 
#    extracted and stored in the %WrkData hash. If defined, the chinkId's data
#    processor is called.
#
# CALLING SYNTAX:
#    $result = &ProcessWrkFile($WrkFileData, $WrkData, $WrkGlobal);
#
# ARGUMENTS:
#    $WrkFileData      Pointer to input data to process.
#    $WrkData          Pointer to hash for data storage.
#    $WrkGlobal        Pointer to WRK global data hash.
#
# RETURNED VALUES:
#    0 = Success,  1 = Error.
#
# ACCESSED GLOBAL VARIABLES:
#    None.
# =============================================================================
sub ProcessWrkFile {
   my ($WrkFileData, $WrkData, $WrkGlobal) = @_;
   my ($chunkId, $chunkLen, @lenBytes);
   my $unkn = 1;   my %unknList = ();

   # Convert input to hex byte format. Used for splice processing and to 
   # simplify debug output.
   my @wrkBytes = ();
   push (@wrkBytes, sprintf("%02X", ord $_)) foreach (split //, $$WrkFileData);
   my($maxDataLen) = scalar @wrkBytes;

   # Save the WRK file version data.
   my @data = splice(@wrkBytes, 0, 11);
   my $debugPnt = 11;
   &DisplayDebug(1,"ProcessWrkFile: @data");
   $$WrkGlobal{'version'} = join('.', chr(48 + $data[10]), chr(48 + $data[9]));

   # Walk through the remaining data untill the end of $wrkBytes or END_CHUNK;
   # Splice removes the processed bytes from the @wrkBytes array. Thus, the
   # next chunkId will always be the first array byte unless we improperly
   # prosessed a chunk record length.
   while ($#wrkBytes >= 0) {
      &DisplayDebug(1,"ProcessWrkFile --> input offset: " . sprintf '0x%X', $debugPnt);
      $chunkId = splice(@wrkBytes, 0, 1);
      if ($chunkId eq 'FF') {               # We're done; found END_CHUNK.
         &DisplayDebug(1,"ProcessWrkFile chunkId: 0xFF - $$WrkData{$chunkId}{'name'}");
         last;
      }
      if ($chunkId eq '00' or $chunkId gt '5F' ) {
         &ColorMessage("Invalid chunkId: $chunkId. The file is corrupt.",
                       "BRIGHT_RED", '');
         return 1;
      }
      @lenBytes = splice(@wrkBytes, 0, 4);
      $debugPnt += 5;
      # WRK file length bytes are stored in little-endian order. Get them in reverse.
      $chunkLen =  hex($lenBytes[3])*16777216 + hex($lenBytes[2])*65536 +
                   hex($lenBytes[1])*256 + hex($lenBytes[0]);
      if ($chunkLen > $maxDataLen) {
         &ColorMessage("Invalid chunkLen: @lenBytes for chunkId $chunkId. The file " .
                       "is corrupt.", "BRIGHT_RED", '');
         return 1;
      }
      
      # Process the chunk. Store chunk bytes in the working array. Then call the chunk 
      # processor using 'subr' dispatch linkage. 
      if (exists($$WrkData{$chunkId})) {
         @{ $$WrkData{'00'}{'chunkbytes'} } = splice(@wrkBytes, 0, $chunkLen);
         $debugPnt += $chunkLen;
         &DisplayDebug(1,"ProcessWrkFile chunkId: 0x$chunkId - " .
                         "$$WrkData{$chunkId}{'name'}   lenBytes: @lenBytes   " .
                         "chunkLen: $chunkLen");
         # Call the chunk data processor.
         return 1 if ( $$WrkData{$chunkId}{'subr'}->($WrkData, $chunkId) );
      }
      else {
         @data = splice(@wrkBytes, 0, $chunkLen);
         $debugPnt += $chunkLen;
         if (defined( $cliOpts{u} )) {
            unless (exists($unknList{$chunkId})) {
               $unknList{$chunkId}{'name'} = join('', 'UNKN_CHUNK', $unkn++);
               &ColorMessage("ProcessWrkFile ignored unknown chunkId: 0x$chunkId   " .
                             "data: @data", "BRIGHT_YELLOW", '');
            }
         }
      }
   }
   # Remove UNKN chunkIds from %WrkData hash for potential next file. This way, 
   # unknown chunkIds are reported per file.
   foreach my $chunkId (keys(%unknList)) {
      delete($$WrkData{$chunkId});
   }
   return 0;
}

# =============================================================================
# MAIN PROGRAM
# =============================================================================
# Process user specified CLI options.
my $allOpts = '';
foreach my $op (keys(%cliOpts)) {
   $allOpts = join('', $allOpts, $cliOpts{$op}) if (defined($cliOpts{$op}));
}

# ==========
# Display program help if -h specified.
if (defined( $cliOpts{h} )) {
   &ColorMessage("$UsageText", "WHITE", '');
   exit(0);  
}

# ==========
# Set debug output default if only -d specified.
if (defined( $cliOpts{d} )) {
   unless ($cliOpts{d} =~ m/^\d[m]?$/i) {
      &ColorMessage("Specify debug level 1-3. Add m for monochrome.", "BRIGHT_RED", '');
      exit(1);
   }
}

# ==========
# Dump hex bytes of specified file if -x is specified.
if (defined( $cliOpts{x} ) ) {
   if (-e $cliOpts{x}) {
      my $fileData;   my @fileBytes = ();
      my $cnt = &ReadData($cliOpts{x}, \$fileData, 10000000);
      exit(1) if ($cnt < 0);
      &DisplayDebug(1,"Read $cnt bytes from $cliOpts{x}");
      push (@fileBytes, sprintf("%02X", ord $_)) foreach (split //, $fileData);
      while (scalar @fileBytes > 0) {
         my @data = splice(@fileBytes, 0, 32);
         print "@data\n";
      }
      exit(0);
   }
   else {
      &ColorMessage("File not found: $cliOpts{x}", "BRIGHT_RED", '');
      exit(1);
   }
}

# ==========
# Check a MIDI file.
if (defined( $cliOpts{c} ) ) {
   my $result = &CheckMidiFile($cliOpts{c}, \%KeySig);
   exit($result);
}

# ==========
# Verify syxtool is available if user specified an option that needs it.
if (defined( $cliOpts{m} ) or defined( $cliOpts{M} ) or defined( $cliOpts{s} )) {
   unless (-e $Syxmidi) {
      &ColorMessage("Required tool syxmidi not found: $Syxmidi", "BRIGHT_RED", '');
      exit(1);
   }
}

# ==========
# Build the %Devices hash. The syxmidi tool is used to detect the available ALSA
# MIDI devices. The hash is populated with both RawMidi and Sequencer device Ids.
# RawMidi devices must be used with sysex data transmission. Sequencer devices are
# used with MIDI file playback.
my %Devices = ();
my @midiDevs = `$Syxmidi -l`;               # Get available ALSA RawMidi devices
splice(@midiDevs, 0, 1);                    # Discard headline.
if (scalar @midiDevs > 0) {
   foreach my $midiDevRec (@midiDevs) {
      chomp($midiDevRec);
      my ($dir, $rawDev, $name) = $midiDevRec =~ m/^(\S+)\s+(\S+)\s+(.+)$/;
      my $port = substr($rawDev, rindex($rawDev, ',')+1);
      $Devices{'raw'}{$port}{'dir'} = $dir;
      $Devices{'raw'}{$port}{'dev'} = $rawDev;
      $Devices{'raw'}{$port}{'name'} = $name;
      &DisplayDebug(1,"RawMidi device: dir: $dir  port: $port  " .
                      "dev: $Devices{'raw'}{$port}{'dev'}  " .
                      "name: $Devices{'raw'}{$port}{'name'}");
   }
}
@midiDevs = `$Syxmidi -L`;               # Get available ALSA sequencer devices
splice(@midiDevs, 0, 1);                 # Discard headline.
if (scalar @midiDevs > 0) {
   foreach my $midiDevRec (@midiDevs) {
      chomp($midiDevRec);
      $midiDevRec =~ s/^\s+//;
      my ($dev, $name) = $midiDevRec =~ m/^(\S+)\s+(.+)$/;
      next if ($name =~ m/Midi Through/);  # Skip MIDI Through device.
      my $port = substr($dev, rindex($dev, ':')+1);
      $Devices{'seq'}{$port}{'dev'} = $dev;
      $Devices{'seq'}{$port}{'name'} = $name;
      &DisplayDebug(1,"Seq device: port: $port  " .
                      "dev: $Devices{'seq'}{$port}{'dev'}  " .
                      "name: $Devices{'seq'}{$port}{'name'}");
   }
}

# ==========
# Show available MIDI devices.
if (defined($cliOpts{m})) {
   exit(&ShowMidiDevices(\%Devices));
}

# ==========
# Process user specified rawmidi port remapping. Replace %Devices content with 
# remapped entries. Unspecified devices are unaffected. 
if (defined($cliOpts{M})) {
   my $rawDevRef = $Devices{'raw'};
   if (scalar keys(%$rawDevRef) == 0) {
      &ColorMessage("No rawmidi devices found.", "BRIGHT_YELLOW", '');
      exit(1);
   }
   my %remap = ();
   &DisplayDebug(1,"cliOpts{M}: $cliOpts{M}");
   my @maps = split(';', $cliOpts{M});
   my $mPort = 0;
   foreach my $srch (@maps) {
      &DisplayDebug(1,"srch: $srch");
      if ($srch ne '') {
         my $found = 0;
         foreach my $port (sort {$a <=> $b} keys %{$rawDevRef}) {
            if ($rawDevRef->{$port}{'dev'} =~ m/$srch/ or 
                $rawDevRef->{$port}{'name'} =~ m/$srch/) {
               $remap{'raw'}{$mPort}{'dev'} = $rawDevRef->{$port}{'dev'};
               $remap{'raw'}{$mPort}{'name'} = $rawDevRef->{$port}{'name'};
               $found = 1;
               last;
            }
         }
         if ($found == 0) {
            &ColorMessage("Unmatched device search term: '$srch'", "BRIGHT_RED", '');
            exit(1);
         }
      }
      else {
         $remap{'raw'}{$mPort}{'dev'} = $rawDevRef->{$mPort}{'dev'};
         $remap{'raw'}{$mPort}{'name'} = $rawDevRef->{$mPort}{'name'};
      }
      $mPort++;
   }
   # Copy remaining devices if mapped less that available devices.
   while ($mPort < scalar keys(%$rawDevRef)) {
      $remap{'raw'}{$mPort}{'dev'} = $rawDevRef->{$mPort}{'dev'};
      $remap{'raw'}{$mPort}{'name'} = $rawDevRef->{$mPort}{'name'};
      $mPort++;
   }
   
   if (scalar keys(%remap) > 0) {
      &ColorMessage("The following port -> MIDI device mapping(s) will be used:",
                    "WHITE", '');
      $Devices{'raw'} = $remap{'raw'};              
      my $rawDevRef = $Devices{'raw'};        # Need to refresh hash pointer.
      foreach my $port (sort {$a <=> $b} keys %{$rawDevRef}) {
         &ColorMessage("   port $port -> $rawDevRef->{$port}{'dev'} - " .
                       "$rawDevRef->{$port}{'name'}","WHITE", '');
      }
   }
}      

# ==========
# Send specified file to MIDI port. Either .sxd or .syx file can be specified.
# The -p option value 'auto' is not available for .syx files.
if (defined( $cliOpts{s} )) {
   my $portOpt = '';
   $portOpt = $cliOpts{p} if (defined( $cliOpts{p} ));
   if ($cliOpts{s} =~ m/\.syx$/ and $portOpt eq 'auto') {
      &ColorMessage("Can't use -p auto with .syx files.", "BRIGHT_RED", '');
      exit(1);
   }
   my $xmitDelay = 250;            # Throttle default.
   if (defined( $cliOpts{z} )) {
      if ($cliOpts{z} =~ m/^(\d+)$/) {
         $xmitDelay = $1;
      }
      else {   
         &ColorMessage("Invalid -z value: $cliOpts{z}", "BRIGHT_RED", '');
         exit(1);
      }
   }
   
   # Load the file data into a working hash. A .syx file does not have any section
   # identifier data. Its raw binary is converted into an array of hex bytes. The
   # sysex in .sxd files is a character string representing the sysex data. Two 
   # characters are joined for each array byte.
   my %sxdFileData = ();   my $bank = 1;
   if ($cliOpts{s} =~ m/\.syx$/) {
      my $sysexData;
      my $cnt = &ReadData($cliOpts{s}, \$sysexData, 10000000);
      exit(1) if ($cnt < 0);
      &DisplayDebug(1,"Read $cnt bytes from $cliOpts{s}");
      my @bytes = ();
      push (@bytes, sprintf("%02X", ord $_)) foreach (split //, $sysexData);
      @{ $sxdFileData{$bank}{'sysx'} } = @bytes;
      my($name, $dir, $suffix) = fileparse($cliOpts{s});
      $sxdFileData{$bank}{'name'} = $name;
      $sxdFileData{$bank}{'port'} = 0;
      $sxdFileData{$bank}{'auto'} = ' no';
   }
   elsif ($cliOpts{s} =~ m/\.sxd$/) {    
      my @sxdArray = ();
      exit(1) if (&ReadFile($cliOpts{s}, \@sxdArray, 'trim'));
      foreach my $rec (@sxdArray) {
         if ($rec =~ m/^(auto|port|name|sysx):\s*(.+)/i) {
            my ($key, $value) = ($1, $2);
            &DisplayDebug(1,"key: $key   value: $value");
            if ($key eq 'sysx') {
               my @nibs = split('', $value);
               my @bytes = ();
               for (my $x = 0; $x < $#nibs; $x += 2) {
                  push (@bytes, join('', $nibs[$x], $nibs[$x+1]) );
               }
               @{ $sxdFileData{$bank}{'sysx'} } = @bytes;
               &DisplayDebug(1,"bank: $bank   auto: $sxdFileData{$bank}{'auto'}" .
                  "   port: $sxdFileData{$bank}{'port'}" .
                  "   name: $sxdFileData{$bank}{'name'}" .
                  "   sysx length: " . scalar @{ $sxdFileData{$bank}{'sysx'} });
               $bank += 1;
            }
            else {
               $sxdFileData{$bank}{$key} = $value;
            }
         }
      }
   }
   else {
      &ColorMessage("Unknown file type: $cliOpts{s}", "BRIGHT_RED", '');
      exit(1);
   }
    
   if (scalar keys(%sxdFileData) > 0) {
      exit( &ProcessSxdFile(\%sxdFileData, \%Devices, $portOpt, $xmitDelay, 
                            $Syxmidi));
   }
   else {
      &ColorMessage("No useable sysex data in file: $cliOpts{s}", 
                    "BRIGHT_RED", '');
      exit(1);
   }
   exit(0);
}

# ==========
# Assemble the file(s) to process.
my @fileList = ();
if (scalar(@ARGV) > 0) {
   foreach my $file (@ARGV) {
      if (-d $file) {
         push (@fileList, grep { -f } glob "$file/*.wrk");
      }
      elsif ($file =~ m/\*/ or $file =~ m/\?/) {
         $file = join('.', $file, 'wrk') unless ($file =~ m/\.wrk$/i);
         push (@fileList, grep { -f } glob "$file");
      }
      elsif ($file =~ m/\.wrk$/i) {
         if ($file =~ m#/|\\#) {
            push (@fileList, $file);
         }
         else {
            push (@fileList, "./$file");
         }
      }   
   }
   &DisplayDebug(1,"FileList: @fileList");
}
if (scalar @fileList == 0) {
   &ColorMessage("No Cakewalk WRK file.", "BRIGHT_RED", '');
   exit(1);
}
 
# ==========
# Validate and process the user specified file(s).
foreach my $file (@fileList) {
   my $wrkFileData;
   my $cnt = &ReadData($file, \$wrkFileData, 10000000);
   next if ($cnt < 0);
   &DisplayDebug(1,"Read $cnt bytes from $file");
   if ($wrkFileData =~ m/^cakewalk/i) {
      &ColorMessage("Processing file: $file ...", "WHITE", '');
      exit(1) if (&ProcessWrkFile(\$wrkFileData, \%WrkData, \%WrkGlobal));
   }
   else {
      &ColorMessage("Not a Cakewalk WRK file: $file", "BRIGHT_RED", '');
      next;
   }
   
   # ----------
   # Show user the extracted data if -v was specified.
   if (defined( $cliOpts{v} )) {
      &ShowExtractedData($file, \%WrkGlobal, \%CakeVars, \%WrkVariables, 
         \%WrkStringTable, \%WrkMarkers, \%MemRegionData, \%KeySig,
         \%SysexBank, \%TrackData, \%TempoData, \%MeterData);
      next;   
   }

   # Create file path and file name working variables.
   my($fName, $fPath, $suffix) = fileparse($file);
   &DisplayDebug(1,"file: $file   fPath: $fPath   fName: $fName   " .
                   "WRK version: $WrkGlobal{'version'}");

   # ----------
   # For -f and/or -e option, generate the corresponding sysex file.
   if (defined( $cliOpts{f} ) or defined( $cliOpts{e} )) {
      my @sysexKeys = sort {$a <=> $b} keys(%SysexBank);
      if (scalar @sysexKeys > 0) {
         my $bankList = join(',', @sysexKeys);
         if (defined( $cliOpts{f} )) {
            my $syxFile = $fName;
            $syxFile =~ s/\.wrk$/\.sxd/i ;
            &DisplayDebug(1,"Creating sysex file: $syxFile ...");
            exit(1) if (&CreateSysexFile(\%SysexBank, $bankList, $fPath, $syxFile));
         }
         if (defined( $cliOpts{e} )) { 
            my $syxFile = $fName;
            $syxFile =~ s/\.wrk$/\.syx/i ;
            &DisplayDebug(1,"Creating sysex file: $syxFile ...");
            exit(1) if (&CreateSysexFile(\%SysexBank, $bankList, $fPath, $syxFile));
         }
      }
   }
   
   # ----------
   # Generate MIDI file if data is available.
   my @trackKeys = sort {$a <=> $b} keys(%TrackData);
   if (scalar @trackKeys > 0) {
      my $trackList = join(',', @trackKeys);  # Default to all tracks
      if (defined( $cliOpts{t} )) {  # Validate user specified list.
         my @temp = split(',', $cliOpts{t} );
         foreach my $trk (@temp) {
            unless (exists($TrackData{$trk})) {
               &ColorMessage("-t track '$trk' not found.", "BRIGHT_RED", '');
               exit(1);
            }
         }
         $trackList = $cliOpts{t};  # Use user specified track list.
      }
      my $addSyx = defined($cliOpts{a}) ? 'yes' : 'no';
      my $adjust = defined($cliOpts{n}) ? 'no' : 'yes';
      my $midiFile = $fName;
      $midiFile =~ s/wrk$/mid/i;
      exit(1) if (&CreateMidiFile(\%TrackData, \%SysexBank, \%TempoData, \%MeterData,
                  \%WrkGlobal, $trackList, $fPath, $midiFile, $addSyx, $adjust));

   # ----------
   # Show a summary of the processed WRK file.
      &ColorMessage("\n" . '-' x 50, '');
      &ColorMessage("Summary for $fName", "WHITE", '');
      my $msg = "WRK file specified adjustments were applied.";
      $msg =~ s/applied\.$/not applied\./ if ($adjust eq 'no');
      &ColorMessage("$msg", "WHITE", '');

      my @sysexKeys = sort {$a <=> $b} keys(%SysexBank);
      if (defined( $cliOpts{f} ) or defined( $cliOpts{e} )) {
         if (scalar @sysexKeys > 0) {      
            &ColorMessage("\nSysex:  Bank\tAuto\tPort\tLength\tName", "WHITE", '');
            &ColorMessage("        ----\t----\t----\t-----\t----------", "WHITE", '');
            foreach my $key (@sysexKeys) {
               &ColorMessage("         $key\t $SysexBank{$key}{'auto'}\t " .
                  "$SysexBank{$key}{'port'}\t" . scalar @{ $SysexBank{$key}{'sysex'} } .
                  "\t$SysexBank{$key}{'name'}", "WHITE", '');
            }
         }
         else {
            &ColorMessage("\nNo sysex banks.", "WHITE", '');
         }
      }
      else {
         if (scalar @sysexKeys > 0) { 
            &ColorMessage("Available WRK file sysex banks were not saved.", "WHITE", '');
         }     
      }
      
      my @sumKeys = ('port','channel','eventCnt','patch','offset','pitch','velocity',
                     'volume','pan','name');            
      &ColorMessage("\nTrack\tPort\tChan\tEvents\tPatch\tTime\tKey\tVel\tVol\tPan\tName",
                    "WHITE", '');
      &ColorMessage("-----\t----\t----\t------\t-----\t----\t---\t---\t---\t---\t----------",
                    "WHITE", '');
      foreach my $trk (split(',', $trackList)) {
         my $msg = "$trk";
         foreach my $key (@sumKeys) {
            if (defined($TrackData{$trk}{$key})) {
               my $value = $TrackData{$trk}{$key};
               if ($key eq 'offset') {
                  $value = $value - 0xFFFFFFFF -1 if ($value > 65535); # negative
               }
               elsif ($key eq 'pitch' or $key eq 'velocity') {
                  $value = $value - 256 if ($value > 127);       # negative
               }
               elsif ($key eq 'channel' and $value < 127) {
                  $value++;
               }
               elsif ($key ne 'name' and $key ne 'eventCnt') {
                  $value = $value > 127 ? ' ' : $value;
               }
               $msg = join("\t", $msg, $value);
            }
            elsif ($key eq 'offset') {
               $msg = join("\t", $msg, 0);
            }
            else {
               $msg = join("\t", $msg, ' ');
            }
         }   
         &ColorMessage(" $msg", "WHITE", '');
      }
      &ColorMessage("", "WHITE", '');
   }
   else {
      &ColorMessage("No track data found in $fName", "WHITE", '');
   }
}
exit(0);
