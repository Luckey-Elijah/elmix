# Control-Plane Capability Owns Trusted Rule Bypass

The Engine exposes trusted record operations only through its explicit
`controlPlane` capability, whose collection handles are created privately by
the Engine. Public `RequestContext` describes anonymous or Auth Record callers
and cannot carry a trusted boolean flag, so Access Rules remain enforced for
ordinary Engine and Server calls while Admin Bootstrap and authenticated Admin
API routes retain their deliberate control-plane authority.
