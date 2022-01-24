#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
int i;
for(i=0; argv[i] != NULL; i++) {
	}
if (i != 6) {
	fprintf(stderr, "Wrong number of args (%d)\n", i);
	exit(1);
	}
if (strcmp(argv[1], "-o") != 0) {
	fprintf(stderr, "argv[1] must be -o\n");
	exit(1);
	}
if (strcmp(argv[2], "-a") != 0) {
	fprintf(stderr, "argv[2] must be -a\n");
	exit(1);
	}
if (strcmp(argv[4], "-d") != 0) {
	fprintf(stderr, "argv[4] must be -d\n");
	exit(1);
	}
setuid(geteuid());
setgid(getegid());

execv("/usr/bin/procmail", argv);
}

