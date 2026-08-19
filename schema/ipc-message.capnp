@0xa1b2c3d4e5f600ff;

using T = import "types.capnp";

struct LogParams {
    severity @0 :T.LogLevel;
    domain @1 :Text;
    message @2 :Text;
}
