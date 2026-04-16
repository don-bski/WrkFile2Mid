/*
 *  syxmidi.c - Throttleable RawMIDI write/read sysex data
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   This program borrows heavily from sources related to the ALSA project.
 *   Refer to https://www.alsa-project.org for more information. The code
 *   was developed using Linux Mint 22.3 Zena. It was tested using a USB 
 *   MidiPlus MIDI interface and Emu Proteus 1 and 2. For reference, a -t
 *   value of 200 (200 micro-second delay per sysex byte) was sufficient 
 *   to prevent Emu Proteus device overload during program testing.
 * 
 *   The following command was used to build the program:
 *     gcc syxmidi.c -o syxmidi -lasound
 * 
 *   If asound dependency related messages are reported, use the linux 
 *   package manager, e.g. 'sudo apt install', to install one of amidi, 
 *   aconnect, or pmidi to resolve.
 * 
 *   Change history
 *   v0.1   03-30-2026    Initial code release.
 *   v0.2   04-02-2026    Added -L option.
 */
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <time.h>
#include <alsa/asoundlib.h>
#include <signal.h>
 
static void usage(void) {
    fprintf(stderr, "\n--- syxmidi v0.2 ---\n");
    fprintf(stderr, "Program to send/receive sysex data with ALSA connected MIDI devices. Older\n");
    fprintf(stderr, "equipment may require use of the -t option to slow down the -s or -S sysex\n");
    fprintf(stderr, "data transmission. For sysex reception (-r), the program waits up to 15 sec\n");
    fprintf(stderr, "for a manually initiated sysex data transmission.\n\n");
    fprintf(stderr, "For MIDI devices that support a sysex dump request, the -s or -S option can\n");
    fprintf(stderr, "be used to initiate the sysex transmission. Refer to the MIDI device's user\n");
    fprintf(stderr, "manual. Include the -s/-S option on the CLI with the -r option. The -s/-S\n");
    fprintf(stderr, "sysex will be sent first followed by a wait for the device's sysex response.\n");
    fprintf(stderr, "The response data is written to the -r specified file.\n\n");
    fprintf(stderr, "The -l option shows the available ALSA RawMidi capable devices. For example:\n\n");
    fprintf(stderr, "   Dir  Device     Name\n");
    fprintf(stderr, "   IO   hw:2,0,0   MIDIPLUS TBOX 2x2 Midi In 1\n");
    fprintf(stderr, "   IO   hw:2,0,1   MIDIPLUS TBOX 2x2 Midi In 2\n\n");
    fprintf(stderr, "Use the text in the Device column for the -d <dev> option. The -L option shows\n");
    fprintf(stderr, "the available ALSA sequencer capable devices. For example:\n\n");
    fprintf(stderr, "   Port     Name\n");
    fprintf(stderr, "   24:0     MIDIPLUS TBOX 2x2 Midi Out 1\n");
    fprintf(stderr, "   24:1     MIDIPLUS TBOX 2x2 Midi Out 2\n\n");
    fprintf(stderr, "Use the port value for external MIDI players. e.g. pmidi -p 24:0 mySeq.mid\n\n");
    fprintf(stderr, "Usage: syxmidi -d <dev> [-l|L] [-t <usec>] [-r <file>] [-s <file>] [-S \"F0..F7\"]\n\n");
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "   -h             : Display the program usage help.\n");
    fprintf(stderr, "   -q             : Quiet. Suppress progress messages.\n");
    fprintf(stderr, "   -l             : Show the available RawMidi devices.\n");
    fprintf(stderr, "   -L             : Show the available MIDI sequencer devices.\n");
    fprintf(stderr, "   -d <dev>       : The MIDI device to use.\n");
    fprintf(stderr, "   -r <file>      : Received sysex data into the specified file.\n");
    fprintf(stderr, "   -s <file>      : Send sysex data contained in the specified file.\n");
    fprintf(stderr, "   -S \"F0..F7\"    : Send space separated hex bytes. Multiple -S options\n");
    fprintf(stderr, "                  : may be specified on the CLI.\n");
    fprintf(stderr, "   -t <usec>      : Microsecond time delay after each sysex byte.\n\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "    syxmidi -d hw:2,0,0 -r myData.syx\n");
    fprintf(stderr, "    syxmidi -d hw:2,0,0 -t 500 -s myData.syx\n");
    fprintf(stderr, "    syxmidi -d hw:2,0,1 -S \"F0 18 04 01\" -S \"02 01 00 F7\"\n");
    fprintf(stderr, "    syxmidi -d hw:2,0,1 -r preset.syx -S \"F0 18 04 01 00 40 00 F7\"\n\n");
}

int stop = 0;
static int sysex_delay;
static char *device;
static char *send_file_name;
static char *receive_file_name;
static char *send_hex;
static unsigned char *send_data;
static int send_data_length;
static int list_all;

void sighandler(int dum) {
    stop = 1;
}

static void *my_malloc(size_t size) {
    void *p = malloc(size);
    if (!p) {
        fprintf(stderr,"Out of memory\n");
        exit(EXIT_FAILURE);
    }
    return p;
}

static void add_send_hex_data(const char *str) {
    int length;
    char *s;

    length = (send_hex ? strlen(send_hex) + 1 : 0) + strlen(str) + 1;
    s = (char *)my_malloc(length);
    if (send_hex) {
        strcpy(s, send_hex);
        strcat(s, " ");
    } else {
        s[0] = '\0';
    }
    strcat(s, str);
    free(send_hex);
    send_hex = s;
}

static int hex_value(char c) {
    if ('0' <= c && c <= '9')
        return c - '0';
    if ('A' <= c && c <= 'F')
        return c - 'A' + 10;
    if ('a' <= c && c <= 'f')
        return c - 'a' + 10;
    fprintf(stderr,"Invalid -S character %c\n", c);
    return -1;
}

static void parse_data(void) {
    const char *p;
    int i, value;

    send_data = (unsigned char *)my_malloc(strlen(send_hex)); /* guesstimate */
    i = 0;
    value = -1;               /* value is >= 0 after read of first hex digit */
    for (p = send_hex; *p; ++p) {
        int digit;
        if (isspace((unsigned char)*p)) {
            if (value >= 0) {
                send_data[i++] = value;
                value = -1;
            }
            continue;
        }
        digit = hex_value(*p);
        if (digit < 0) {
            send_data = NULL;
            return;
        }
        if (value < 0) {
            value = digit;
        } else {
            send_data[i++] = (value << 4) | digit;
            value = -1;
        }
    }
    if (value >= 0)
        send_data[i++] = value;
    send_data_length = i;
}

static void list_device(snd_ctl_t *ctl, int card, int device) {
    snd_rawmidi_info_t *info;
    const char *name;
    const char *sub_name;
    int subs, subs_in, subs_out;
    int sub;
    int err;

    snd_rawmidi_info_alloca(&info);
    snd_rawmidi_info_set_device(info, device);
    snd_rawmidi_info_set_stream(info, SND_RAWMIDI_STREAM_INPUT);
    err = snd_ctl_rawmidi_info(ctl, info);
    if (err >= 0)
        subs_in = snd_rawmidi_info_get_subdevices_count(info);
    else
        subs_in = 0;

    snd_rawmidi_info_set_stream(info, SND_RAWMIDI_STREAM_OUTPUT);
    err = snd_ctl_rawmidi_info(ctl, info);
    if (err >= 0)
        subs_out = snd_rawmidi_info_get_subdevices_count(info);
    else
        subs_out = 0;

    subs = subs_in > subs_out ? subs_in : subs_out;
    if (!subs)
        return;

    for (sub = 0; sub < subs; ++sub) {
        snd_rawmidi_info_set_stream(info, sub < subs_in ?
            SND_RAWMIDI_STREAM_INPUT : SND_RAWMIDI_STREAM_OUTPUT);
        snd_rawmidi_info_set_subdevice(info, sub);
        err = snd_ctl_rawmidi_info(ctl, info);
        if (err < 0) {
            fprintf(stderr,"cannot get rawmidi information %d:%d:%d: %s\n",
                card, device, sub, snd_strerror(err));
            return;
        }
        name = snd_rawmidi_info_get_name(info);
        sub_name = snd_rawmidi_info_get_subdevice_name(info);
        if (sub == 0 && sub_name[0] == '\0') {
            printf("%c%c  hw:%d,%d    %s",
                   sub < subs_in ? 'I' : ' ',
                   sub < subs_out ? 'O' : ' ',
                   card, device, name);
            if (subs > 1)
                printf(" (%d subdevices)", subs);
            putchar('\n');
            break;
        } else {
            printf("%c%c  hw:%d,%d,%d  %s\n",
                   sub < subs_in ? 'I' : ' ',
                   sub < subs_out ? 'O' : ' ',
                   card, device, sub, sub_name);
        }
    }
}

static void list_card_devices(int card) {
    snd_ctl_t *ctl;
    char name[32];
    int device;
    int err;

    sprintf(name, "hw:%d", card);
    if ((err = snd_ctl_open(&ctl, name, 0)) < 0) {
        fprintf(stderr,"cannot open control for card %d: %s", card, snd_strerror(err));
        return;
    }
    device = -1;
    for (;;) {
        if ((err = snd_ctl_rawmidi_next_device(ctl, &device)) < 0) {
            fprintf(stderr,"cannot determine device number: %s", snd_strerror(err));
            break;
        }
        if (device < 0)
            break;
        list_device(ctl, card, device);
    }
    snd_ctl_close(ctl);
}

static void device_list(void) {
    int card, err;

    card = -1;
    if ((err = snd_card_next(&card)) < 0) {
        fprintf(stderr,"cannot determine card number: %s", snd_strerror(err));
        return;
    }
    if (card < 0) {
        fprintf(stderr,"no sound card found");
        return;
    }
    puts("Dir Device    Name");
    do {
        list_card_devices(card);
        if ((err = snd_card_next(&card)) < 0) {
            fprintf(stderr,"cannot determine card number: %s", snd_strerror(err));
            break;
        }
    } while (card >= 0);
}

static void showlist() {
    snd_seq_client_info_t *cinfo;
    snd_seq_port_info_t *pinfo;
    int  client;
    int  err;
    snd_seq_t *handle;

    err = snd_seq_open(&handle, "hw", SND_SEQ_OPEN_DUPLEX, 0);
    if (err < 0)
        fprintf(stderr,"Could not open sequencer %s", snd_strerror(errno));
    snd_seq_client_info_alloca(&cinfo);
    snd_seq_client_info_set_client(cinfo, -1);
    printf(" Port   Port name\n");

    while (snd_seq_query_next_client(handle, cinfo) >= 0) {
        client = snd_seq_client_info_get_client(cinfo);
        snd_seq_port_info_alloca(&pinfo);
        snd_seq_port_info_set_client(pinfo, client);
        snd_seq_port_info_set_port(pinfo, -1);
        while (snd_seq_query_next_port(handle, pinfo) >= 0) {
            int  cap;
            cap = (SND_SEQ_PORT_CAP_SUBS_WRITE|SND_SEQ_PORT_CAP_WRITE);
            if ((snd_seq_port_info_get_capability(pinfo) & cap) == cap) {
                printf("%3d:%-3d %s\n",
                    snd_seq_port_info_get_client(pinfo),
                    snd_seq_port_info_get_port(pinfo),
                    // snd_seq_client_info_get_name(cinfo),
                    snd_seq_port_info_get_name(pinfo));
            }
        }
    }
}

// ========== main ==========// 
int main(int argc,char** argv) {
    sysex_delay = 0;
    device = NULL;
    send_file_name = NULL;
    receive_file_name = NULL;
    send_hex = NULL;
    send_data = NULL;
    int do_send_hex = 0;
    snd_rawmidi_t *dev_in = NULL;
    snd_rawmidi_t *dev_out = NULL;
    int quiet = 0;

    int c;
    while ((c = getopt(argc, argv, "hqlLt:d:r:s:S:")) != -1) {
        switch (c) {
        case 'h':
            usage();
            return 0;
        case 'q':
            quiet = 1;
            break;
        case 't':
            sysex_delay = atoi(optarg);
            break;
        case 'l':
            device_list();
            return 0;
            break;
        case 'L':
            showlist();
            return 0;
            break;
        case 'd':
            device = optarg;
            break;
        case 'r':
            receive_file_name = optarg;
            break;
        case 's':
            send_file_name = optarg;
            break;
        case 'S':
            do_send_hex = 1;
            if (optarg)
                add_send_hex_data(optarg);
            break;
        default:
            fprintf(stderr,"Unsupported option %s. See help.\n", argv[optind]);
                return 1;
        }
    }

    if (do_send_hex) {
        /* data for -S can be specified as multiple arguments */
        if (!send_hex && !argv[optind]) {
            fprintf(stderr,"Please specify some sysex with -S option.");
            return 1;
        }
        for (; argv[optind]; ++optind)
            add_send_hex_data(argv[optind]);
            
        if (quiet == 0)
            fprintf(stdout,"CLI sysex: %s\n", send_hex);
        /* Parse_data validates the -S input and converts it to binary */
        /* bytes. The result is returned in send_data. NULL is error.  */
        parse_data();
        if (send_data == NULL)
           return 1;
    } else {
        if (argv[optind]) {
            fprintf(stderr,"%s is not an option.", argv[optind]);
               return 1;
        }
    }

    if (device) {
        int status;
        int mode = SND_RAWMIDI_NONBLOCK;
        if ((status = snd_rawmidi_open(&dev_in, NULL, device, mode)) < 0) { 
            fprintf(stderr,"Open for MIDI In failed: %s: %d\n", device,status);
            return 1;
        }
        if ((status = snd_rawmidi_open(NULL, &dev_out, device, 0)) < 0) { 
            fprintf(stderr,"Open for MIDI Out failed: %s: %d\n", device,status);
            return 1;
        }
        if (quiet == 0)
            fprintf(stdout,"Device %s is connected.\n", device);
    } else {
        fprintf(stderr,"Specify a MIDI device with the -d option.\n");
        return 1;
    }

    /* Send -S specified sysex data to device. */
    if (send_data) {
        int i;
        if (quiet == 0)
            fprintf(stdout,"Sending sysex using %i usec delay between bytes.\n", sysex_delay);
        for (i = 0; i < send_data_length; i++) {
            // printf("i: %d - %02X\n", i, send_data[i]);
            snd_rawmidi_write(dev_out, send_data+i, sizeof(char));
            snd_rawmidi_drain(dev_out);
            usleep(sysex_delay);
        }
        free(send_data);
        if (quiet == 0)
            fprintf(stdout,"Transmission complete.\n");
    }

    /* Send sysex data in specified file to device. */
    if (send_file_name) {
        unsigned char *buffer; 
        unsigned long file_size;
        
        // Read the file.
        FILE *fp = fopen(send_file_name, "rb");
        if (fp == NULL) {
            fprintf(stderr,"Can't open file %s: %s\n", send_file_name, strerror(errno));
            return 1;
        }
        fseek(fp, 0, SEEK_END);
        file_size = ftell(fp);
        if (file_size < 1) {
            fprintf(stderr,"Can't get size of %s\n", send_file_name);
            fclose(fp);
            return 1;
        }   
        fseek(fp, 0, SEEK_SET);
        buffer = (unsigned char *)malloc(file_size * sizeof(char));
        if (buffer == NULL) {
           fprintf(stderr,"buffer memory error for size %lu\n", file_size);
           fclose(fp);
           return 1;
        }
        if (fread(buffer, sizeof(char), file_size, fp) != file_size) {
            fprintf(stderr,"Can't read from file %s: %s\n", send_file_name, strerror(errno));
           fclose(fp);
           return 1;
        }
        fclose(fp);
        if (quiet == 0)
            fprintf(stdout,"Read %lu bytes from %s\n", file_size, send_file_name);
              
        /* Send sysex data to device. */
        int i;
        if (quiet == 0)
            fprintf(stdout,"Sending sysex using %i usec delay between bytes.\n", sysex_delay);
        for (i = 0; i < file_size; i++) {
            // printf("i: %d - %02X\n", i, buffer[i]);
            snd_rawmidi_write(dev_out, buffer+i, sizeof(char));
            snd_rawmidi_drain(dev_out);
            usleep(sysex_delay);
        }
        free(buffer);
        if (quiet == 0)
            fprintf(stdout,"Transmission complete.\n");
    }

    // Receive sysex data from device and write to the specified file. A ctrl-c
    // input handler is enabled. When input, the 'stop' global variable is set 
    // to terminate the main while loop.
    if (receive_file_name) {
        signal(SIGINT,sighandler);
        unsigned char *buffer;
        int bufSize = 32768;
        buffer = (unsigned char *)malloc(bufSize * sizeof(char));
        if (buffer == NULL) {
           fprintf(stderr,"buffer memory error for size %d\n", bufSize);
           return 1;
        }
        int byteCnt = 0;
        int sleepTime = 250000;    // Main loop delay; 250 msec.
        int userWait = 15;         // Wait time for user initiated sysex transfer.
        int timeout = sleepTime * 4 * userWait;
        if (quiet == 0)
            fprintf(stdout,"Waiting up to %d seconds for sysex from %s\n", userWait, device);
        int status, newSize;
        unsigned char byte_in[1];
        while (stop == 0 && timeout > 0) {
            status = 0;
            while (status != -EAGAIN) {
                status = snd_rawmidi_read(dev_in, byte_in, 1);
                if ((status < 0) && (status != -EBUSY) && (status != -EAGAIN)) {
                    fprintf(stderr,"MIDI read error: %s\n", snd_strerror(status));
                } else if (status >= 0) {
                    if (byteCnt == 0) 
                        if (quiet == 0)
                            fprintf(stdout,"Receiving MIDI data ...\n");
                    buffer[byteCnt++] = byte_in[0];
                    if (byteCnt > bufSize) {            // realloc if at end
                        newSize = byteCnt + 256;
                        buffer = (unsigned char*)realloc(buffer, newSize * sizeof(char));
                        if (buffer == NULL) {
                            fprintf(stderr,"buffer memory error for size %d\n", newSize);
                            dev_in = NULL;
                            return 1;
                        }
                        bufSize = newSize;
                    }
                    timeout = sleepTime * 3;           // wait .5 sec for more data.
                }
            }
            usleep(sleepTime);
            timeout -= sleepTime;
        }
        if (quiet == 0)
            fprintf(stdout,"Read %d bytes from %s\n", byteCnt, device);
        
        // Store sysex in buffer to specified file.
        if (byteCnt > 0) {
            FILE *fp = fopen(receive_file_name, "wb");
            if (fp == NULL) {
                fprintf(stderr,"Can't open file %s: %s\n", receive_file_name, strerror(errno));
                return 1;
            }
            size_t wrote = fwrite(buffer, sizeof(char), byteCnt, fp);
            fclose(fp);
            if (quiet == 0)
                fprintf(stdout,"File %s created.\n", receive_file_name);
        }
        free(buffer);
    }  
    snd_rawmidi_close(dev_in);
    snd_rawmidi_close(dev_out);
    return 0;
}
