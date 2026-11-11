#include "systemcalls.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static bool execute_command(char *const command[], const char *outputfile)
{
    if (command == NULL || command[0] == NULL ||
        (outputfile != NULL && outputfile[0] == '\0')) {
        return false;
    }

    fflush(NULL);
    pid_t child = fork();
    if (child < 0) {
        return false;
    }

    if (child == 0) {
        if (outputfile != NULL) {
            int output_fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (output_fd < 0) {
                _exit(EXIT_FAILURE);
            }
            if (dup2(output_fd, STDOUT_FILENO) < 0) {
                close(output_fd);
                _exit(EXIT_FAILURE);
            }
            if (output_fd != STDOUT_FILENO) {
                close(output_fd);
            }
        }

        execv(command[0], command);
        _exit(EXIT_FAILURE);
    }

    int status;
    pid_t waited;
    do {
        waited = waitpid(child, &status, 0);
    } while (waited < 0 && errno == EINTR);

    return waited == child && WIFEXITED(status) &&
           WEXITSTATUS(status) == EXIT_SUCCESS;
}

static bool execute_variadic(const char *outputfile, int count, va_list args)
{
    if (count < 1 || (size_t)count > SIZE_MAX / sizeof(char *) - 1) {
        return false;
    }

    char **command = calloc((size_t)count + 1, sizeof(*command));
    if (command == NULL) {
        return false;
    }

    va_list command_args;
    va_copy(command_args, args);
    for (int i = 0; i < count; i++) {
        command[i] = va_arg(command_args, char *);
        if (command[i] == NULL) {
            va_end(command_args);
            free(command);
            return false;
        }
    }
    va_end(command_args);

    bool success = execute_command(command, outputfile);
    free(command);
    return success;
}

/**
 * @param cmd the command to execute with system()
 * @return true if the command in @param cmd was executed
 *   successfully using the system() call, false if an error occurred,
 *   either in invocation of the system() call, or if a non-zero return
 *   value was returned by the command issued in @param cmd.
*/
bool do_system(const char *cmd)
{
    if (cmd == NULL) {
        return false;
    }

    int status = system(cmd);
    return status != -1 && WIFEXITED(status) &&
           WEXITSTATUS(status) == EXIT_SUCCESS;
}

/**
* @param count -The numbers of variables passed to the function. The variables are command to execute.
*   followed by arguments to pass to the command
*   Since exec() does not perform path expansion, the command to execute needs
*   to be an absolute path.
* @param ... - A list of 1 or more arguments after the @param count argument.
*   The first is always the full path to the command to execute with execv()
*   The remaining arguments are a list of arguments to pass to the command in execv()
* @return true if the command @param ... with arguments @param arguments were executed successfully
*   using the execv() call, false if an error occurred, either in invocation of the
*   fork, waitpid, or execv() command, or if a non-zero return value was returned
*   by the command issued in @param arguments with the specified arguments.
*/

bool do_exec(int count, ...)
{
    va_list args;
    va_start(args, count);
    bool success = execute_variadic(NULL, count, args);
    va_end(args);
    return success;
}

/**
* @param outputfile - The full path to the file to write with command output.
*   This file will be closed at completion of the function call.
* All other parameters, see do_exec above
*/
bool do_exec_redirect(const char *outputfile, int count, ...)
{
    if (outputfile == NULL || outputfile[0] == '\0') {
        return false;
    }

    va_list args;
    va_start(args, count);
    bool success = execute_variadic(outputfile, count, args);
    va_end(args);
    return success;
}
