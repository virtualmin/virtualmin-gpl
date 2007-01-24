#include <stdio.h>

int main(int argc, char **argv)
{
setuid(geteuid());
setgid(getegid());

execv("/usr/bin/procmail", argv);
}

