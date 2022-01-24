#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
int i;
for(i=0; argv[i] != NULL; i++) {
	}
if (i != 6) {
	fprintf(stderr, "Wrong number of args (%d)\n", i);
	return 1;
	}
if (strcmp(argv[1], "-o") != 0) {
	fprintf(stderr, "argv[1] must be -o\n");
	return 1;
	}
if (strcmp(argv[2], "-a") != 0) {
	fprintf(stderr, "argv[2] must be -a\n");
	return 1;
	}
if (strcmp(argv[4], "-d") != 0) {
	fprintf(stderr, "argv[4] must be -d\n");
	return 1;
	}
setuid(geteuid());
setgid(getegid());

execv("/usr/bin/procmail", argv);
return 0;
}

