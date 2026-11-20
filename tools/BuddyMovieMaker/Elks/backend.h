/* Native ELKS backend for the first-party WZR1 player. GPL-3.0. */
#ifndef BUDDY_ELKS_BACKEND_H
#define BUDDY_ELKS_BACKEND_H
struct screen_info {
    unsigned old_mode, old_rows, installed_rows, installed_scanline;
    unsigned restored_mode, restored_rows;
    int release_error;
};
extern struct screen_info screen_info;
extern const char *screen_error;
unsigned long clock_ms(void);
int screen_open(void);
void screen_close(void);
int stop_requested(void);
void fill_cells(unsigned cell,unsigned count,unsigned char value);
void copy_cells(unsigned cell,unsigned count,const unsigned char *source);
int snapshot(const char *path);
#endif
