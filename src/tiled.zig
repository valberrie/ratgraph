const Str = []const u8;
pub const Tileset = struct {
    backgroundcolor: Str,
    fillmode: Str,

    class: Str,
    columns: i32,
    firstgid: i32,

    image: Str,
    imageheight: i32,
    imagewidth: i32,
    margin: i32,
    name: Str,
    spacing: i32,
    tilecount: i32,
    tileheight: i32,
    tilewidth: i32,

    tiledversion: Str = "1.10.2",
    type: Str = "tileset",
    version: Str = "1.10",
};

pub const TilesetRef = struct {
    firstgid: i32,
    source: Str,
};
