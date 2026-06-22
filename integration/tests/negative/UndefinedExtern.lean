-- @[extern] to a C symbol with no implementation provided: linking MUST fail (undefined symbol).
@[extern "rl4_no_such_function"]
opaque missing : UInt32

def main : IO Unit := IO.println s!"{missing}"
