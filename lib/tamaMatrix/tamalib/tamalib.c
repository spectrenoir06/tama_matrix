/*
 * TamaLIB - A hardware agnostic Tamagotchi P1 emulation library
 *
 * Copyright (C) 2021 Jean-Christophe Rona <jc@rona.fr>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */
#include "tamalib.h"
#include "hw.h"
#include "cpu.h"
#include "hal.h"

#include "stdlib.h"
#include <time.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdio.h>

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <string.h>
#include <getopt.h>

typedef struct {
	unsigned char matrix[32][16];
	unsigned char icones[8];
} tama_data_t;


typedef struct {
	uint32_t id;
	uint32_t matrix[16];
	uint8_t icones;
} tama_data_bin_t;

tama_data_t data;
tama_data_bin_t data_bin;


#define DEFAULT_FRAMERATE				30 // fps

static exec_mode_t exec_mode = EXEC_MODE_RUN;

static u32_t step_depth = 0;

static timestamp_t screen_ts = 0;

static u32_t ts_freq;

static u8_t g_framerate = DEFAULT_FRAMERATE;

hal_t *g_hal;


bool_t tamalib_init(const u12_t *program, breakpoint_t *breakpoints, u32_t freq)
{
	bool_t res = 0;

	res |= cpu_init(program, breakpoints, freq);
	res |= hw_init();

	ts_freq = freq;

	return res;
}

void tamalib_release(void)
{
	hw_release();
	cpu_release();
}

void tamalib_set_framerate(u8_t framerate)
{
	g_framerate = framerate;
}

u8_t tamalib_get_framerate(void)
{
	return g_framerate;
}

void tamalib_register_hal(hal_t *hal)
{
	g_hal = hal;
}

void tamalib_set_exec_mode(exec_mode_t mode)
{
	exec_mode = mode;
	step_depth = cpu_get_depth();
	cpu_sync_ref_timestamp();
}

void tamalib_step(void)
{
	if (exec_mode == EXEC_MODE_PAUSE) {
		return;
	}
	// printf("step\n");

	if (cpu_step()) {
		exec_mode = EXEC_MODE_PAUSE;
		step_depth = cpu_get_depth();
	} else {
		switch (exec_mode) {
			case EXEC_MODE_PAUSE:
			case EXEC_MODE_RUN:
				break;

			case EXEC_MODE_STEP:
				exec_mode = EXEC_MODE_PAUSE;
				break;

			case EXEC_MODE_NEXT:
				if (cpu_get_depth() <= step_depth) {
					exec_mode = EXEC_MODE_PAUSE;
					step_depth = cpu_get_depth();
				}
				break;

			case EXEC_MODE_TO_CALL:
				if (cpu_get_depth() > step_depth) {
					exec_mode = EXEC_MODE_PAUSE;
					step_depth = cpu_get_depth();
				}
				break;

			case EXEC_MODE_TO_RET:
				if (cpu_get_depth() < step_depth) {
					exec_mode = EXEC_MODE_PAUSE;
					step_depth = cpu_get_depth();
				}
				break;
		}
	}
}

void tamalib_mainloop(void)
{
	timestamp_t ts;

	while (!g_hal->handler()) {
		tamalib_step();

		/* Update the screen @ g_framerate fps */
		ts = g_hal->get_timestamp();
		if (ts - screen_ts >= ts_freq/g_framerate) {
			screen_ts = ts;
			g_hal->update_screen();
		}
	}
}


log_level_t log_levels = LOG_ERROR;

static void* hal_malloc(u32_t size) {
	return malloc(size);
}

static void hal_free(void* ptr) {
	free(ptr);
}

static void hal_halt(void) {
	// exit(EXIT_SUCCESS);
}

static bool_t hal_is_log_enabled(log_level_t level) {
	return !!(log_levels & level);
}

static void hal_log(log_level_t level, char* buff, ...) {
	// va_list arglist;

	// if (!(log_levels & level)) {
	// 	return;
	// }

	// va_start(arglist, buff);

	// vfprintf((level == LOG_ERROR) ? stderr : stdout, buff, arglist);

	// va_end(arglist);
}



static timestamp_t hal_get_timestamp(void) {
	struct timespec time;

	clock_gettime(CLOCK_REALTIME, &time);
	return (time.tv_sec * 1000000 + time.tv_nsec / 1000);
}

// #define NO_SLEEP 

static void hal_sleep_until(timestamp_t ts) {
	struct timespec t;
	int remaining = (int)(ts - hal_get_timestamp());

	/* Sleep for a bit more than what is needed */
	if (remaining > 0) {
		t.tv_sec = remaining / 1000000;
		t.tv_nsec = (remaining % 1000000) * 1000;
		nanosleep(&t, NULL);
	}
}
// static bool_t matrix_buffer[LCD_HEIGHT][LCD_WIDTH] = { {0} };
// static bool_t matrix_buffer_old[LCD_HEIGHT][LCD_WIDTH] = { {0} };

// static bool_t icone_buffer[8] = { 0 };
// static bool_t icone_buffer_old[8] = { 0 };


static void hal_update_screen(void) {
}


static void hal_set_lcd_matrix(u8_t x, u8_t y, bool_t val) {
	// printf("%d, %d, = %d\n", x, y, val);
	data.matrix[x][y] = val;
	// int id = x+y*32;
	// int i = (id/32)
	if (val)
		data_bin.matrix[y] |= 1 << x;
	else
		data_bin.matrix[y] &= ~(1 << x);
}

static void hal_set_lcd_icon(u8_t icon, bool_t val) {
	data.icones[icon] = val;
	if (val)
		data_bin.icones |= 1 << icon;
	else
		data_bin.icones &= ~(1 << icon);
}

u32_t g_freq = 0;

static void hal_set_frequency(u32_t freq) {
	// if (current_freq != freq) {
	// 	current_freq = freq;
	// 	sin_pos = 0;
	// }
	g_freq = freq;
}

static void hal_play_frequency(bool_t en) {
	// if (is_audio_playing != en) {
	// 	is_audio_playing = en;
	// }
	if (en) {
	}
}


static int hal_handler(void) {
	return 0;
}


#include "rom.h"

static hal_t hal = {
	.malloc = &hal_malloc,
	.free = &hal_free,
	.halt = &hal_halt,
	.is_log_enabled = &hal_is_log_enabled,
	.log = &hal_log,
	.sleep_until = &hal_sleep_until,
	.get_timestamp = &hal_get_timestamp,
	.update_screen = &hal_update_screen,
	.set_lcd_matrix = &hal_set_lcd_matrix,
	.set_lcd_icon = &hal_set_lcd_icon,
	.set_frequency = &hal_set_frequency,
	.play_frequency = &hal_play_frequency,
	.handler = &hal_handler,
};

static breakpoint_t* g_breakpoints = NULL;

void lua_tamalib_init(uint32_t id){
	data_bin.id = id;
	tamalib_register_hal(&hal);
	tamalib_init(g_program, g_breakpoints, 1000000); // my_breakpoints can be NULL, 1000000 means that timestamps will be expressed in us
}


void lua_tamalib_step() {
	tamalib_step();
}

tama_data_t *lua_tamalib_get_data() {
	return &data;
}

unsigned char lua_tamalib_get_matrix_data(int x, int y) {
	return data.matrix[x][y];
}

void lua_tamalib_get_matrix_data_bin(uint8_t *ptr) {
	memcpy(ptr, (uint8_t*)&data_bin, sizeof(data_bin));
	// return data_bin;
}

void lua_tamalib_bigstep(void) {
	timestamp_t ts;
	while(1) {
	// while (!g_hal->handler()) {
		tamalib_step();

		/* Update the screen @ g_framerate fps */
		ts = g_hal->get_timestamp();
		if (ts - screen_ts >= ts_freq / g_framerate) {
			screen_ts = ts;
			// g_hal->update_screen();
			return;

		}
	}
}

void lua_tamalib_set_press_A() {
	tamalib_set_button(BTN_LEFT, BTN_STATE_PRESSED);
}

void lua_tamalib_set_release_A() {
	tamalib_set_button(BTN_LEFT, BTN_STATE_RELEASED);
}

void lua_tamalib_set_press_B() {
	tamalib_set_button(BTN_MIDDLE, BTN_STATE_PRESSED);
}

void lua_tamalib_set_release_B() {
	tamalib_set_button(BTN_MIDDLE, BTN_STATE_RELEASED);
}

void lua_tamalib_set_press_C() {
	tamalib_set_button(BTN_RIGHT, BTN_STATE_PRESSED);
}

void lua_tamalib_set_release_C() {
	tamalib_set_button(BTN_RIGHT, BTN_STATE_RELEASED);
}



