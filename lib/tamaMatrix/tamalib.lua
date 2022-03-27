local ffi = require("ffi")
local lib = ffi.load("lib/tamaMatrix/tamalib/libtama.so")

ffi.cdef(
[[
typedef enum {
	LOG_ERROR	= 0x1,
	LOG_INFO	= (0x1 << 1),
	LOG_MEMORY	= (0x1 << 2),
	LOG_CPU		= (0x1 << 3),
} log_level_t;

/* The Hardware Abstraction Layer
 * NOTE: This structure acts as an abstraction layer between TamaLIB and the OS/SDK.
 * All pointers MUST be implemented, but some implementations can be left empty.
 */
typedef struct {
	/* Memory allocation functions
	 * NOTE: Needed only if breakpoints support is required.
	 */
	void * (*malloc)(unsigned int size);
	void (*free)(void *ptr);

	/* What to do if the CPU has halted
	 */
	void (*halt)(void);

	/* Log related function
	 * NOTE: Needed only if log messages are required.
	 */
	bool (*is_log_enabled)(log_level_t level);
	void (*log)(log_level_t level, char *buff, ...);

	/* Clock related functions
	 * NOTE: Timestamps granularity is configured with tamalib_init(), an accuracy
	 * of ~30 us (1/32768) is required for a cycle accurate emulation.
	 */
	void (*sleep_until)(unsigned int ts);
	unsigned int (*get_timestamp)(void);

	/* Screen related functions
	 * NOTE: In case of direct hardware access to pixels, the set_XXXX() functions
	 * (called for each pixel/icon update) can directly drive them, otherwise they
	 * should just store the data in a buffer and let update_screen() do the actual
	 * rendering (at 30 fps).
	 */
	void (*update_screen)(void);
	void (*set_lcd_matrix)(unsigned char x, unsigned char y, bool val);
	void (*set_lcd_icon)(unsigned char icon, bool val);

	/* Sound related functions
	 * NOTE: set_frequency() changes the output frequency of the sound, while
	 * play_frequency() decides whether the sound should be heard or not.
	 */
	void (*set_frequency)(unsigned int freq);
	void (*play_frequency)(bool en);

	/* Event handler from the main app (if any)
	 * NOTE: This function usually handles button related events, states loading/saving ...
	 */
	int (*handler)(void);
} hal_t;

extern hal_t *g_hal;

typedef struct{
	unsigned char matrix[32][16];
	unsigned char icones[8];
} tama_data_t;

void lua_tamalib_init(uint32_t id);
void lua_tamalib_step();
void lua_tamalib_bigstep();
tama_data_t *lua_tamalib_get_data();
unsigned char lua_tamalib_get_matrix_data(int x, int y);

void lua_tamalib_set_press_A();
void lua_tamalib_set_release_A(); 

void lua_tamalib_set_press_B();
void lua_tamalib_set_release_B(); 

void lua_tamalib_set_press_C();
void lua_tamalib_set_release_C();

void lua_tamalib_get_matrix_data_bin(unsigned char *ptr);

typedef struct {
	unsigned int matrix[16];
	unsigned char icones;
} tama_data_bin_t;

]]
)

-- lib.ws2811_init(self.strip)

return lib