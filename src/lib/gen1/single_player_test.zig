const calc = @import("calc.zig");
const chance = @import("chance.zig");
const common = @import("../common/data.zig");
const data = @import("data.zig");
const helpers = @import("helpers.zig");
const mechanics = @import("mechanics.zig");
const pkmn = @import("../pkmn.zig");
const protocol = @import("../common/protocol.zig");
const std = @import("std");

const Choice = common.Choice;
const EXP = helpers.EXP;
const Move = data.Move;
const Pokemon = helpers.Pokemon;
const Species = data.Species;
const SinglePlayer = mechanics.SinglePlayer;

/// Single-player battles draw from the overworld `Random`, which is close to uniform (unlike the link-battle list).
const Uniform = extern struct {
    x: u64,

    pub fn next(self: *Uniform) u8 {
        self.x ^= self.x << 13;
        self.x ^= self.x >> 7;
        self.x ^= self.x << 17;
        return @truncate(self.x >> 32);
    }
};

/// A trainer Pokémon: fixed DVs (attack 9, defense 8, speed 8, special 8) and no stat experience.
fn enemy(species: Species, level: u8, moves: []const Move) Pokemon {
    return .{
        .species = species,
        .level = level,
        .moves = moves,
        .dvs = .{ .atk = 9, .def = 8, .spe = 8, .spc = 8 },
        .stats = .{ .hp = 0, .atk = 0, .def = 0, .spe = 0, .spc = 0 },
    };
}

/// Plays `n` battles of a level 100 Weedle (perfect DVs, max stat experience, all badges) using only Poison Sting
/// against a trainer, and returns how many it won.
fn weedle(class: u8, team: []const Pokemon, n: u32) !u32 {
    const p1 = [_]Pokemon{.{ .species = .Weedle, .moves = &.{ .PoisonSting, .StringShot } }};
    var wins: u32 = 0;
    var buf: [pkmn.CHOICES_SIZE]Choice = undefined;
    for (0..n) |i| {
        var sp = SinglePlayer{ .p2 = .{ .class = class }, .badges = 0xFF };
        var options = .{ .log = protocol.NULL, .chance = chance.NULL, .calc = calc.NULL, .trainer = &sp };
        var battle = data.Battle(Uniform){
            .rng = .{ .x = 0x9E3779B97F4A7C15 ^ (i + 1) },
            .sides = .{ helpers.Side.init(&p1), helpers.Side.init(team) },
        };
        const pp = battle.side(.P2).pokemon;
        var result = try battle.update(.{}, .{}, &options);
        while (result.type == .None) {
            const c1: Choice = if (result.p1 == .Pass) .{} else c1: {
                _ = battle.choices(.P1, result.p1, &buf);
                break :c1 if (buf[0].type == .Move and buf[0].data != 0) .{ .type = .Move, .data = 1 } else buf[0];
            };
            const c2: Choice = switch (result.p2) {
                .Pass => .{},
                .Switch => .{ .type = .Switch, .data = @intCast(mechanics.trainerReplacement(battle.side(.P2))) },
                .Move => if (battle.choices(.P2, .Move, &buf) == 1) buf[0] else .{
                    .type = .Move,
                    .data = mechanics.trainerMove(&battle, .P2, &sp.p2),
                },
            };
            result = try battle.update(c1, c2, &options);
        }
        wins += @intFromBool(result.type == .Win);
        // Enemy trainers never spend PP
        for (battle.side(.P2).pokemon, pp) |after, before| {
            for (after.moves, before.moves) |a, b| try std.testing.expectEqual(b.pp, a.pp);
        }
    }
    return wins;
}

test "single player: badge boosts on switch-in" {
    const p1 = [_]Pokemon{.{ .species = .Weedle, .moves = &.{.PoisonSting} }};
    const p2 = [_]Pokemon{enemy(.Gengar, 56, &.{.NightShade})};
    var sp = SinglePlayer{ .p2 = .{ .class = 46 }, .badges = 0b0101_0101 };
    var options = .{ .log = protocol.NULL, .chance = chance.NULL, .calc = calc.NULL, .trainer = &sp };
    var battle = data.Battle(Uniform){
        .rng = .{ .x = 1 },
        .sides = .{ helpers.Side.init(&p1), helpers.Side.init(&p2) },
    };
    _ = try battle.update(.{}, .{}, &options);
    const stored = battle.side(.P1).stored().stats;
    const active = battle.side(.P1).active.stats;
    try std.testing.expectEqual(stored.atk + stored.atk / 8, active.atk);
    try std.testing.expectEqual(stored.def + stored.def / 8, active.def);
    try std.testing.expectEqual(stored.spe + stored.spe / 8, active.spe);
    try std.testing.expectEqual(stored.spc + stored.spc / 8, active.spc);
}

test "single player: Weedle against the Elite Four" {
    if (pkmn.options.showdown) return error.SkipZigTest;
    const lance = [_]Pokemon{
        enemy(.Gyarados, 58, &.{ .DragonRage, .Leer, .HydroPump, .HyperBeam }),
        enemy(.Dragonair, 56, &.{ .Agility, .Slam, .DragonRage, .HyperBeam }),
        enemy(.Dragonair, 56, &.{ .Agility, .Slam, .DragonRage, .HyperBeam }),
        enemy(.Aerodactyl, 60, &.{ .Supersonic, .Bite, .TakeDown, .HyperBeam }),
        enemy(.Dragonite, 62, &.{ .Agility, .Slam, .Barrier, .HyperBeam }),
    };
    const bruno = [_]Pokemon{
        enemy(.Onix, 53, &.{ .RockThrow, .Rage, .Slam, .Harden }),
        enemy(.Hitmonchan, 55, &.{ .IcePunch, .ThunderPunch, .MegaPunch, .Counter }),
        enemy(.Hitmonlee, 55, &.{ .JumpKick, .FocusEnergy, .HighJumpKick, .MegaKick }),
        enemy(.Onix, 56, &.{ .RockThrow, .Rage, .Slam, .Harden }),
        enemy(.Machamp, 58, &.{ .Leer, .FocusEnergy, .Fissure, .Submission }),
    };
    const agatha = [_]Pokemon{
        enemy(.Gengar, 56, &.{ .ConfuseRay, .NightShade, .Hypnosis, .DreamEater }),
        enemy(.Golbat, 56, &.{ .Supersonic, .ConfuseRay, .WingAttack, .Haze }),
        enemy(.Haunter, 55, &.{ .ConfuseRay, .NightShade, .Hypnosis, .DreamEater }),
        enemy(.Arbok, 58, &.{ .Bite, .Glare, .Screech, .Acid }),
        enemy(.Gengar, 60, &.{ .ConfuseRay, .NightShade, .Toxic, .DreamEater }),
    };
    const n = 20000;
    const l = try weedle(47, &lance, n);
    const b = try weedle(33, &bruno, n);
    const a = try weedle(46, &agatha, n);
    std.debug.print("\nWeedle wins in {d}: Lance {d}, Bruno {d}, Agatha {d}\n", .{ n, l, b, a });
}

/// An AI trainer's choice for `player` given the request type.
fn aiChoice(battle: anytype, player: common.Player, request: Choice.Type, sp: *SinglePlayer) Choice {
    var buf: [pkmn.CHOICES_SIZE]Choice = undefined;
    return switch (request) {
        .Pass => .{},
        .Switch => .{ .type = .Switch, .data = @intCast(mechanics.trainerReplacement(battle.side(player))) },
        .Move => if (battle.choices(player, .Move, &buf) == 1) buf[0] else .{
            .type = .Move,
            .data = mechanics.trainerMove(battle, player, sp.get(player)),
        },
    };
}

/// Trainer vs trainer, both played by the cartridge AI under the enemy rules; a draw after 1000 turns.
fn mirror(c1: u8, t1: []const Pokemon, c2: u8, t2: []const Pokemon, n: u32) ![3]u32 {
    var out = [3]u32{ 0, 0, 0 };
    for (0..n) |i| {
        var sp = SinglePlayer{ .p1 = .{ .class = c1 }, .p2 = .{ .class = c2 }, .mirror = true };
        var options = .{ .log = protocol.NULL, .chance = chance.NULL, .calc = calc.NULL, .trainer = &sp };
        var battle = data.Battle(Uniform){
            .rng = .{ .x = 0xD1B54A32D192ED03 ^ (i + 1) },
            .sides = .{ helpers.Side.init(t1), helpers.Side.init(t2) },
        };
        const before = .{ battle.side(.P1).pokemon, battle.side(.P2).pokemon };
        var result = try battle.update(.{}, .{}, &options);
        var turns: u32 = 0;
        while (result.type == .None and turns < 1000) : (turns += 1) {
            const a = aiChoice(&battle, .P1, result.p1, &sp);
            const b = aiChoice(&battle, .P2, result.p2, &sp);
            result = try battle.update(a, b, &options);
        }
        out[switch (result.type) {
            .Win => 0,
            .Lose => 1,
            else => 2,
        }] += 1;
        // Neither AI trainer spends PP
        inline for (.{ .P1, .P2 }, 0..) |player, k| {
            for (battle.side(player).pokemon, before[k]) |after, start| {
                for (after.moves, start.moves) |x, y| try std.testing.expectEqual(y.pp, x.pp);
            }
        }
    }
    return out;
}

test "single player: mirror (trainer vs trainer)" {
    const lance = [_]Pokemon{
        enemy(.Gyarados, 58, &.{ .DragonRage, .Leer, .HydroPump, .HyperBeam }),
        enemy(.Dragonair, 56, &.{ .Agility, .Slam, .DragonRage, .HyperBeam }),
        enemy(.Dragonair, 56, &.{ .Agility, .Slam, .DragonRage, .HyperBeam }),
        enemy(.Aerodactyl, 60, &.{ .Supersonic, .Bite, .TakeDown, .HyperBeam }),
        enemy(.Dragonite, 62, &.{ .Agility, .Slam, .Barrier, .HyperBeam }),
    };
    const brock = [_]Pokemon{
        enemy(.Geodude, 12, &.{ .Tackle, .DefenseCurl }),
        enemy(.Onix, 14, &.{ .Tackle, .Screech, .Bide }),
    };
    const r = try mirror(47, &lance, 34, &brock, 2000);
    std.debug.print("\nLance vs Brock in 2000: {d}-{d}-{d}\n", .{ r[0], r[1], r[2] });
    try std.testing.expectEqual(@as(u32, 2000), r[0]);
    const s = try mirror(47, &lance, 47, &lance, 2000);
    std.debug.print("Lance vs Lance in 2000: {d}-{d}-{d}\n", .{ s[0], s[1], s[2] });
    try std.testing.expect(s[0] > 700 and s[1] > 700);
}
