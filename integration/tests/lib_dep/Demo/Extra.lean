-- Intra-set module of the dependent target. It shares the `Demo` namespace prefix with the dep
-- (`Demo.Core`, in a separate lean_library) and imports it, so resolving this import requires
-- finding `Demo.Core.olean` in the dependency's olean tree even though `Demo.Extra.olean` is written
-- into the dependent target's own tree.
import Demo.Core

namespace Demo

def extra : Nat := answer + 1

end Demo
