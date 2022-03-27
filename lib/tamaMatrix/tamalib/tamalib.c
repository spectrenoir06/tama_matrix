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
	uint32_t id;
	uint32_t matrix[16];
	uint8_t icones;
	uint8_t playSound;
	uint32_t freq;
} tama_data_bin_t;

tama_data_bin_t data_bin[2];

// uint8_t flip = 0;


#define DEFAULT_FRAMERATE				60 // fps

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

	printf("sizeof(tama_data_bin_t) = %d\n", sizeof(tama_data_bin_t));

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
	if (val)
		data_bin[0].matrix[y] |= 1 << x;
	else
		data_bin[0].matrix[y] &= ~(1 << x);
	
	if (x == 31 && y == 15) {
		memcpy(&data_bin[1], &data_bin[0], sizeof(tama_data_bin_t));
	}
}

static void hal_set_lcd_icon(u8_t icon, bool_t val) {
	if (val)
		data_bin[0].icones |= 1 << icon;
	else
		data_bin[0].icones &= ~(1 << icon);
}

// u32_t g_freq = 0;

static void hal_set_frequency(u32_t freq) {
	// if (current_freq != freq) {
	// 	current_freq = freq;
	// 	sin_pos = 0;
	// }
	// printf("hal_set_frequency(%d)\n", freq);
	data_bin[0].freq = freq;
	data_bin[1].freq = freq;
	// g_freq = freq;
}

static void hal_play_frequency(bool_t en) {
	// if (is_audio_playing != en) {
	// 	is_audio_playing = en;
	// }
	// printf("hal_play_frequency(%d)\n", en);
	if (en) {
		data_bin[0].playSound = 1;
		data_bin[1].playSound = 1;
	}
	else {
		data_bin[0].playSound = 0;
		data_bin[1].playSound = 0;
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
	data_bin[0].id = id;
	tamalib_register_hal(&hal);
	tamalib_init(g_program, g_breakpoints, 1000000); // my_breakpoints can be NULL, 1000000 means that timestamps will be expressed in us
}

void lua_tamalib_step() {
	tamalib_step();
}

void lua_tamalib_get_matrix_data_bin(uint8_t *ptr) {
	memcpy(ptr, (uint8_t*)&data_bin[1], sizeof(tama_data_bin_t));
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

void lua_tamalib_set_speed(uint32_t speed) {
	tamalib_set_speed(speed);
}

void lua_tamalib_state_save(uint8_t *buf) {
	// SDL_RWops* f;
	state_t* state;
	// uint8_t buf[4];
	// uint32_t num = 0;
	uint32_t i;

	state = tamalib_get_state();

	/* First the magic, then the version, and finally the fields of
	 * the state_t struct written as u8, u16 little-endian or u32
	 * little-endian following the struct order
	 */

	uint32_t ctn = 0;

	// buf[ctn++] = (uint8_t)STATE_FILE_MAGIC[0];
	// buf[ctn++] = (uint8_t)STATE_FILE_MAGIC[1];
	// buf[ctn++] = (uint8_t)STATE_FILE_MAGIC[2];
	// buf[ctn++] = (uint8_t)STATE_FILE_MAGIC[3];
	// // num += SDL_RWwrite(f, buf, 4, 1);

	// buf[ctn++] = STATE_FILE_VERSION & 0xFF;
	// // num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->pc) & 0xFF;
	buf[ctn++] = (*(state->pc) >> 8) & 0x1F;
	// num += SDL_RWwrite(f, buf, 2, 1);

	buf[ctn++] = *(state->x) & 0xFF;
	buf[ctn++] = (*(state->x) >> 8) & 0xF;
	// num += SDL_RWwrite(f, buf, 2, 1);

	buf[ctn++] = *(state->y) & 0xFF;
	buf[ctn++] = (*(state->y) >> 8) & 0xF;
	// num += SDL_RWwrite(f, buf, 2, 1);

	buf[ctn++] = *(state->a) & 0xF;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->b) & 0xF;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->np) & 0x1F;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->sp) & 0xFF;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->flags) & 0xF;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->tick_counter) & 0xFF;
	buf[ctn++] = (*(state->tick_counter) >> 8) & 0xFF;
	buf[ctn++] = (*(state->tick_counter) >> 16) & 0xFF;
	buf[ctn++] = (*(state->tick_counter) >> 24) & 0xFF;
	// num += SDL_RWwrite(f, buf, 4, 1);

	buf[ctn++] = *(state->clk_timer_timestamp) & 0xFF;
	buf[ctn++] = (*(state->clk_timer_timestamp) >> 8) & 0xFF;
	buf[ctn++] = (*(state->clk_timer_timestamp) >> 16) & 0xFF;
	buf[ctn++] = (*(state->clk_timer_timestamp) >> 24) & 0xFF;
	// num += SDL_RWwrite(f, buf, 4, 1);

	buf[ctn++] = *(state->prog_timer_timestamp) & 0xFF;
	buf[ctn++] = (*(state->prog_timer_timestamp) >> 8) & 0xFF;
	buf[ctn++] = (*(state->prog_timer_timestamp) >> 16) & 0xFF;
	buf[ctn++] = (*(state->prog_timer_timestamp) >> 24) & 0xFF;
	// num += SDL_RWwrite(f, buf, 4, 1);

	buf[ctn++] = *(state->prog_timer_enabled) & 0x1;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->prog_timer_data) & 0xFF;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->prog_timer_rld) & 0xFF;
	// num += SDL_RWwrite(f, buf, 1, 1);

	buf[ctn++] = *(state->call_depth) & 0xFF;
	buf[ctn++] = (*(state->call_depth) >> 8) & 0xFF;
	buf[ctn++] = (*(state->call_depth) >> 16) & 0xFF;
	buf[ctn++] = (*(state->call_depth) >> 24) & 0xFF;
	// num += SDL_RWwrite(f, buf, 4, 1);

	for (i = 0; i < INT_SLOT_NUM; i++) {
		buf[ctn++] = state->interrupts[i].factor_flag_reg & 0xF;
		// num += SDL_RWwrite(f, buf, 1, 1);

		buf[ctn++] = state->interrupts[i].mask_reg & 0xF;
		// num += SDL_RWwrite(f, buf, 1, 1);

		buf[ctn++] = state->interrupts[i].triggered & 0x1;
		// num += SDL_RWwrite(f, buf, 1, 1);
	}

	/* First 640 half bytes correspond to the RAM */
	for (i = 0; i < MEM_RAM_SIZE; i++) {
		buf[ctn++] = state->memory[i + MEM_RAM_ADDR] & 0xF;
		// num += SDL_RWwrite(f, buf, 1, 1);
	}

	/* I/Os are from 0xF00 to 0xF7F */
	for (i = 0; i < MEM_IO_SIZE; i++) {
		buf[ctn++] = state->memory[i + MEM_IO_ADDR] & 0xF;
		// num += SDL_RWwrite(f, buf, 1, 1);
	}
	// printf("save done %d\n", ctn);

	// if (num != (17 + INT_SLOT_NUM * 3 + MEM_RAM_SIZE + MEM_IO_SIZE)) {
	// 	fprintf(stderr, "FATAL: Failed to write to state file \"%s\" %u %u !\n", path, num, (23 + INT_SLOT_NUM * 3 + MEMORY_SIZE));
	// }

	// SDL_RWclose(f);
}


void lua_tamalib_state_load(uint8_t* buf) {
	// SDL_RWops* f;
	state_t* state;
	// uint8_t buf[4];
	// uint32_t num = 0;
	uint32_t i;
	uint32_t ctn = 0;

	state = tamalib_get_state();

	// f = SDL_RWFromFile(path, "r");
	// if (f == NULL) {
	// 	fprintf(stderr, "FATAL: Cannot open state file \"%s\" !\n", path);
	// 	return;
	// }

	/* First the magic, then the version, and finally the fields of
	 * the state_t struct written as u8, u16 little-endian or u32
	 * little-endian following the struct order
	 */
	// num += SDL_RWread(f, buf, 4, 1);
	// if (buf[0] != (uint8_t)STATE_FILE_MAGIC[0] || buf[1] != (uint8_t)STATE_FILE_MAGIC[1] ||
	// 	buf[2] != (uint8_t)STATE_FILE_MAGIC[2] || buf[3] != (uint8_t)STATE_FILE_MAGIC[3]) {
	// 	fprintf(stderr, "FATAL: Wrong state file magic in \"%s\" !\n", path);
	// 	return;
	// }

	// num += SDL_RWread(f, buf, 1, 1);
	// if (buf[0] != STATE_FILE_VERSION) {
	// 	fprintf(stderr, "FATAL: Unsupported version %u (expected %u) in state file \"%s\" !\n", buf[0], STATE_FILE_VERSION, path);
	// 	/* TODO: Handle migration at a point */
	// 	return;
	// }

	// num += SDL_RWread(f, buf, 2, 1);
	*(state->pc) = buf[ctn++] | ((buf[ctn++] & 0x1F) << 8);

	// num += SDL_RWread(f, buf, 2, 1);
	*(state->x) = buf[ctn++] | ((buf[ctn++] & 0xF) << 8);

	// num += SDL_RWread(f, buf, 2, 1);
	*(state->y) = buf[ctn++] | ((buf[ctn++] & 0xF) << 8);

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->a) = buf[ctn++] & 0xF;

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->b) = buf[ctn++] & 0xF;

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->np) = buf[ctn++] & 0x1F;

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->sp) = buf[ctn++];

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->flags) = buf[ctn++] & 0xF;

	// num += SDL_RWread(f, buf, 4, 1);
	*(state->tick_counter) = buf[ctn++] | (buf[ctn++] << 8) | (buf[ctn++] << 16) | (buf[ctn++] << 24);

	// num += SDL_RWread(f, buf, 4, 1);
	*(state->clk_timer_timestamp) = buf[ctn++] | (buf[ctn++] << 8) | (buf[ctn++] << 16) | (buf[ctn++] << 24);

	// num += SDL_RWread(f, buf, 4, 1);
	*(state->prog_timer_timestamp) = buf[ctn++] | (buf[ctn++] << 8) | (buf[ctn++] << 16) | (buf[ctn++] << 24);

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->prog_timer_enabled) = buf[ctn++] & 0x1;

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->prog_timer_data) = buf[ctn++];

	// num += SDL_RWread(f, buf, 1, 1);
	*(state->prog_timer_rld) = buf[ctn++];

	// num += SDL_RWread(f, buf, 4, 1);
	*(state->call_depth) = buf[ctn++] | (buf[ctn++] << 8) | (buf[ctn++] << 16) | (buf[ctn++] << 24);

	for (i = 0; i < INT_SLOT_NUM; i++) {
		// num += SDL_RWread(f, buf, 1, 1);
		state->interrupts[i].factor_flag_reg = buf[ctn++] & 0xF;

		// num += SDL_RWread(f, buf, 1, 1);
		state->interrupts[i].mask_reg = buf[ctn++] & 0xF;

		// num += SDL_RWread(f, buf, 1, 1);
		state->interrupts[i].triggered = buf[ctn++] & 0x1;
	}

	/* First 640 half bytes correspond to the RAM */
	for (i = 0; i < MEM_RAM_SIZE; i++) {
		// num += SDL_RWread(f, buf, 1, 1);
		state->memory[i + MEM_RAM_ADDR] = buf[ctn++] & 0xF;
	}

	/* I/Os are from 0xF00 to 0xF7F */
	for (i = 0; i < MEM_IO_SIZE; i++) {
		// num += SDL_RWread(f, buf, 1, 1);
		state->memory[i + MEM_IO_ADDR] = buf[ctn++] & 0xF;
	}

	printf("load %d\n", ctn);

	// if (num != (17 + INT_SLOT_NUM * 3 + MEM_RAM_SIZE + MEM_IO_SIZE)) {
	// 	fprintf(stderr, "FATAL: Failed to read from state file \"%s\" !\n", path);
	// }

	// SDL_RWclose(f);

	tamalib_refresh_hw();
}



