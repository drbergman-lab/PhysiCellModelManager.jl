"""
    quietRun(cmd::Cmd)

Run the command with stdout and stderr redirected to devnull so no output goes to the console.
"""
quietRun(cmd::Cmd) = run(pipeline(cmd, stdout=devnull, stderr=devnull))