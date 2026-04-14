/*
 * Windowed Watchdog test for NWO (No-Way-Out) watchdog
 *
 * This program exits cleanly after configuring/controlling the watchdog,
 * allowing VATF scripts to orchestrate timing measurements and post-reboot
 * verification.
 *
 * Modes:
 *	keepalive			- Continuously pet watchdog at specified delay intervals
 *	trigger_reboot			- Trigger watchdog reboot (no petting)
 *	oneshot				- Pet once after a delay
 *
 * Usage:
 *	nwo_wwd_test -device /dev/watchdog -mode keepalive -delay 30 -count 2
 *	nwo_wwd_test -device /dev/watchdog -mode trigger_reboot
 *	nwo_wwd_test -device /dev/watchdog -mode oneshot -delay 6
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include <errno.h>

#define DEFAULT_DEVICE "/dev/watchdog"
#define DEFAULT_MODE "keepalive"
#define DEFAULT_COUNT 1
#define DEFAULT_DELAY 0

typedef enum {
	MODE_KEEPALIVE,
	MODE_TRIGGER_REBOOT,
	MODE_ONESHOT,
	MODE_UNKNOWN
} wdt_mode_t;

typedef struct {
	char device[256];
	char mode[32];
	int count;
	int delay;
} wdt_options_t;

static wdt_mode_t parse_mode(const char *mode_str) {
	if (strcmp(mode_str, "keepalive") == 0)
		return MODE_KEEPALIVE;
	if (strcmp(mode_str, "trigger_reboot") == 0)
		return MODE_TRIGGER_REBOOT;
	if (strcmp(mode_str, "oneshot") == 0)
		return MODE_ONESHOT;
	return MODE_UNKNOWN;
}

void print_usage(const char *prog) {
	fprintf(stderr,
		"Usage: %s [options]\n"
		"Options:\n"
		"  -device PATH      Watchdog device (default: %s)\n"
		"  -mode MODE        Test mode: keepalive, trigger_reboot, oneshot (default: %s)\n"
		"  -count N          Number of pets (default: %d)\n"
		"  -delay SEC        Delay before pet in seconds (default: %d)\n"
		"  -h                Show this help\n",
	prog, DEFAULT_DEVICE, DEFAULT_MODE,
	DEFAULT_COUNT, DEFAULT_DELAY);
}

int parse_options(int argc, char *argv[], wdt_options_t *opts) {
	struct option long_options[] = {
		{"device", required_argument, NULL, 'd'},
		{"mode", required_argument, NULL, 'm'},
		{"count", required_argument, NULL, 'c'},
		{"delay", required_argument, NULL, 'l'},
		{"help", no_argument, NULL, 'h'},
		{NULL, 0, NULL, 0}
	};

	strncpy(opts->device, DEFAULT_DEVICE, sizeof(opts->device) - 1);
	opts->device[sizeof(opts->device) - 1] = '\0';
	strncpy(opts->mode, DEFAULT_MODE, sizeof(opts->mode) - 1);
	opts->mode[sizeof(opts->mode) - 1] = '\0';
	opts->count = DEFAULT_COUNT;
	opts->delay = DEFAULT_DELAY;

	int opt;
	while ((opt = getopt_long_only(argc, argv, "d:m:c:l:h", long_options, NULL)) != -1) {
		switch (opt) {
		case 'd':
			strncpy(opts->device, optarg, sizeof(opts->device) - 1);
			opts->device[sizeof(opts->device) - 1] = '\0';
			break;
		case 'm':
			strncpy(opts->mode, optarg, sizeof(opts->mode) - 1);
			opts->mode[sizeof(opts->mode) - 1] = '\0';
			break;
		case 'c':
			opts->count = atoi(optarg);
			if (opts->count < 1 || opts->count > 10000) {
				fprintf(stderr, "[nwo_wwd] Invalid count: must be 1-10000\n");
				return -1;
			}
			break;
		case 'l':
			opts->delay = atoi(optarg);
			if (opts->delay < 0 || opts->delay > 65) {
				fprintf(stderr, "[nwo_wwd] Invalid delay: must be 0-65 seconds\n");
				return -1;
			}
			break;
		case 'h':
			print_usage(argv[0]);
			return -1;
		default:
			print_usage(argv[0]);
			return -1;
		}
	}

	return EXIT_SUCCESS;
}

static int nwo_wwd_open(const char *device) {
	int fd;

	fd = open(device, O_WRONLY);
	if (fd == -1)
		return -errno;

	printf("[nwo_wwd] Watchdog started!\n");
	return fd;
}

static int nwo_wwd_close(int fd) {
	if (close(fd) != 0)
		return -errno;

	return 0;
}

static int nwo_wwd_write(int fd) {
	int ret;

	ret = write(fd, "\0", 1);
	if (ret == 1) {
		printf("[nwo_wwd] Watchdog try to pet!\n");
		return 0;
	}

	if (ret < 0)
		return -errno;

	return -EIO;
}

static int nwo_wwd_start(const char *device) {
	int fd;

	fd = nwo_wwd_open(device);
	if (fd < 0)
		return fd;

	return (nwo_wwd_close(fd) == 0) ? 0 : -EIO;
}

int nwo_wwd_pet(int fd, int delay, int loop_cnt) {
	int ret;

	for (int i = 0; i < loop_cnt; i++) {
		sleep(delay);

		printf("[nwo_wwd] Petting: loop %d/%d\n", i + 1, loop_cnt);
		ret = nwo_wwd_write(fd);
		if (ret != 0) {
			fprintf(stderr, "[nwo_wwd] Failed to pet watchdog: %s\n", strerror(-ret));
			return ret;
		}
	}

	return 0;
}

/*
 * Trigger Reboot: Start the watchdog & let timer expire to reboot the
 * system
 */
int nwo_wwd_trigger_reboot(const char *device) {
	int ret;

	ret = nwo_wwd_start(device);
	if (ret != 0) {
		fprintf(stderr, "[nwo_wwd] Failed to start watchdog: %s\n", strerror(-ret));
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}

/*
 * Oneshot: Start the watchdog & pet once after a delay
 */
int nwo_wwd_oneshot(const char *device, int delay) {
	int fd, ret;

	fd = nwo_wwd_open(device);
	if (fd < 0)
		return EXIT_FAILURE;

	ret = nwo_wwd_pet(fd, delay, 1);
	if (ret != 0) {
		fprintf(stderr, "[nwo_wwd] Failed to pet watchdog: %s\n", strerror(-ret));
		nwo_wwd_close(fd);
		return EXIT_FAILURE;
	}

	return (nwo_wwd_close(fd) == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}

/*
 * Keepalive: Start the watchdog & continuously pet after a delay
 * within the valid window
 */
int nwo_wwd_keepalive(const char *device, int delay, int count) {
	int fd, ret;

	fd = nwo_wwd_open(device);
	if (fd < 0)
		return EXIT_FAILURE;

	ret = nwo_wwd_pet(fd, delay, count);
	if (ret != 0) {
		fprintf(stderr, "[nwo_wwd] Failed to pet watchdog: %s\n", strerror(-ret));
		nwo_wwd_close(fd);
		return EXIT_FAILURE;
	}

	return (nwo_wwd_close(fd) == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}

int main(int argc, char *argv[]) {
	wdt_options_t opts;

	if (parse_options(argc, argv, &opts) < 0) {
		return EXIT_FAILURE;
	}

	switch (parse_mode(opts.mode)) {
	case MODE_KEEPALIVE:
		return nwo_wwd_keepalive(opts.device, opts.delay, opts.count);
	case MODE_TRIGGER_REBOOT:
		return nwo_wwd_trigger_reboot(opts.device);
	case MODE_ONESHOT:
		return nwo_wwd_oneshot(opts.device, opts.delay);
	case MODE_UNKNOWN:
		fprintf(stderr, "[nwo_wwd] Unknown mode: %s\n", opts.mode);
		print_usage(argv[0]);
		return EXIT_FAILURE;
	}

	return EXIT_FAILURE;
}
