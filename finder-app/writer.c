#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>

static void report_error(const char *operation, const char *path, int error_number)
{
    const char *reason = strerror(error_number);

    syslog(LOG_ERR, "%s %s: %s", operation, path, reason);
    fprintf(stderr, "Error: %s %s: %s\n", operation, path, reason);
}

int main(int argc, char *argv[])
{
    FILE *output;
    int saved_errno;

    openlog("writer", LOG_PID, LOG_USER);

    if (argc != 3 || argv[1][0] == '\0') {
        syslog(LOG_ERR, "Usage: %s <writefile> <writestr>", argv[0]);
        fprintf(stderr, "Usage: %s <writefile> <writestr>\n", argv[0]);
        closelog();
        return 1;
    }

    syslog(LOG_DEBUG, "Writing %s to %s", argv[2], argv[1]);

    output = fopen(argv[1], "w");
    if (output == NULL) {
        saved_errno = errno;
        report_error("Could not open", argv[1], saved_errno);
        closelog();
        return 1;
    }

    if (fprintf(output, "%s\n", argv[2]) < 0) {
        saved_errno = errno != 0 ? errno : EIO;
        report_error("Could not write to", argv[1], saved_errno);
        (void)fclose(output);
        closelog();
        return 1;
    }

    if (fclose(output) != 0) {
        saved_errno = errno;
        report_error("Could not close", argv[1], saved_errno);
        closelog();
        return 1;
    }

    closelog();
    return 0;
}
