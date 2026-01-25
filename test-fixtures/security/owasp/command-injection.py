# TEST FILE: Contains command injection vulnerability patterns
# For workflow validation - DO NOT use these patterns in production

import os
import subprocess

# VULNERABLE: os.system with user input
def run_user_command(user_input):
    os.system("echo " + user_input)


# VULNERABLE: subprocess with shell=True and user input
def execute_with_shell(filename):
    subprocess.call("cat " + filename, shell=True)


# VULNERABLE: eval with user input
def calculate(expression):
    return eval(expression)  # Code injection


# VULNERABLE: exec with user input
def run_code(code_string):
    exec(code_string)  # Code injection


# VULNERABLE: Popen with shell=True
def get_file_info(filepath):
    proc = subprocess.Popen(
        "ls -la " + filepath,
        shell=True,
        stdout=subprocess.PIPE
    )
    return proc.communicate()[0]


# VULNERABLE: Template command with user input
def git_clone(repo_url):
    command = f"git clone {repo_url} /tmp/repo"
    os.system(command)


# VULNERABLE: String formatting in system call
def backup_file(source, destination):
    os.system("cp %s %s" % (source, destination))


# VULNERABLE: __import__ with user input
def dynamic_import(module_name):
    return __import__(module_name)
