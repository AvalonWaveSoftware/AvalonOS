/*
 * Mirrors iwctl's command_init() option parser (iwd client/command.c):
 *   getopt_long(argc, argv, "u:p:P:dh", command_opts, NULL)
 * with --help / -h, and no POSIXLY_CORRECT. Used by net-menu-test.py
 * so P-M30 / P-L27 checks use real GNU getopt_long, not a mock that
 * accepts any argv.
 */
#include <getopt.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	static const struct option command_opts[] = {
		{ "username", required_argument, NULL, 'u' },
		{ "password", required_argument, NULL, 'p' },
		{ "passphrase", required_argument, NULL, 'P' },
		{ "dontask", no_argument, NULL, 'd' },
		{ "help", no_argument, NULL, 'h' },
		{ 0, 0, 0, 0 }
	};
	int opt;
	int saw_help = 0;
	int saw_err = 0;

	/* iwctl does not set POSIXLY_CORRECT; GNU permutation is in effect. */
	optarg = NULL;
	optind = 1;
	opterr = 0;

	for (;;) {
		opt = getopt_long(argc, argv, "u:p:P:dh", command_opts, NULL);
		if (opt == -1)
			break;
		if (opt == 'h')
			saw_help = 1;
		else if (opt == '?')
			saw_err = 1;
	}

	fputs(saw_err ? "err=1" : "err=0", stdout);
	fprintf(stdout, " help=%d", saw_help);
	fputs(" rest=", stdout);
	for (int i = optind; i < argc; i++) {
		if (i > optind)
			fputc('\t', stdout);
		fputs(argv[i], stdout);
	}
	fputc('\n', stdout);
	return saw_err ? 2 : 0;
}
