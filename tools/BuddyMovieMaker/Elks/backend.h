/* Native ELKS backend for the first-party WZR1 player. GPL-3.0. */
#ifndef BUDDY_ELKS_BACKEND_H
#define BUDDY_ELKS_BACKEND_H
/* 80 hidden cells isolate stock bioshd's character-79 spinner. The visible
 * 8000 cells still end within the existing 8192-cell CGA/Tandy 16K page. */
#define BUDDY_CGA_START 160
#define BUDDY_CGA_END (BUDDY_CGA_START+16000)
#ifndef __ASSEMBLER__
struct screen_info {
    unsigned old_mode, old_rows, installed_rows, installed_scanline;
    unsigned installed_mode,bios_kb,viewport_word;
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
int validate_packet(const unsigned char *commands,unsigned len);
int movie_cache_open(unsigned bytes);
void movie_cache_put(unsigned offset,const void *data,unsigned bytes);
void movie_cache_get(void *data,unsigned offset,unsigned bytes);
int movie_cache_close(void);
int render_packet(const unsigned char *commands);
#endif /* !__ASSEMBLER__ */
#endif
