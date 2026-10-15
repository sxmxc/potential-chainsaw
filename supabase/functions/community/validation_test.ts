import { compatibility, validatePuzzle } from "./validation.ts";

const fixture = JSON.parse(
  await Deno.readTextFile(
    "../../../resources/campaign/01-first-connection.json",
  ),
);
for (const key of ["chapter", "order", "prerequisites", "campaign"]) {
  delete fixture[key];
}
function rejected(puzzle: unknown, catalog: unknown = compatibility) {
  try {
    validatePuzzle(puzzle, catalog);
  } catch {
    return;
  }
  throw new Error("Unsafe submission was accepted");
}
Deno.test("packaged JSON format is accepted without a parallel serializer", () => {
  validatePuzzle(fixture, compatibility);
});
Deno.test("catalog additions do not invalidate supported puzzles or bypass dependency validation", () => {
  validatePuzzle(fixture, "a".repeat(64));
  validatePuzzle(fixture);
  const unsupported = structuredClone(fixture);
  unsupported.pieces[0].piece = "future-unknown-piece";
  rejected(unsupported, "a".repeat(64));
});
Deno.test("unsupported versions, scene paths and impersonated registration are rejected", () => {
  for (
    const [field, value] of [
      ["version", 4],
      ["id", "../escape"],
      ["environment_snapshot", "res://evil.tscn"],
      ["campaign", {}],
      ["bounds", [0, 0, 0, 0, 0, 0]],
      ["permissions", { "missing": { move: true } }],
    ] as const
  ) rejected({ ...fixture, [field]: value });
});
Deno.test("unknown assets, settings, types, link ports and excessive configuration are rejected", () => {
  for (
    const mutate of [
      (p: typeof fixture) => p.pieces[0].piece = "res://evil.tscn",
      (p: typeof fixture) => p.pieces[0].config = { unknown: true },
      (p: typeof fixture) =>
        p.pieces[0].config = { __proto__: null, constructor: true },
      (p: typeof fixture) => p.pieces[0].config.release_speed = 10000,
      (p: typeof fixture) => p.pieces[0].config.release_speed = "bad",
      (p: typeof fixture) =>
        p.pieces[0].config.links = [{
          event: "released",
          target: "goal",
          action: "missing",
        }],
      (p: typeof fixture) => p.inventory = JSON.parse('{"__proto__":2}'),
      (p: typeof fixture) =>
        p.environment_instances = [{
          uid: "evil",
          asset: "../../evil",
          position: [0, 0, 0],
          rotation: 0,
        }],
      (p: typeof fixture) => p.solution[0].rotation = 4,
      (p: typeof fixture) => p.objectives[0].target = "missing",
      (p: typeof fixture) => p.validation.physics_success = false,
    ]
  ) {
    const p = structuredClone(fixture);
    mutate(p);
    rejected(p);
  }
});

Deno.test("mounted controls accept compatible state wiring and reject unsafe mount metadata", () => {
  const p = structuredClone(fixture);
  const support = p.pieces[0];
  const memory = {
    uid: "memory",
    piece: "logic-memory",
    position: [...support.position],
    rotation: 0,
    config: {
      initial_state: true,
      mount_target: support.uid,
      mount_basis: [1, 0, 0, 0, 1, 0, 0, 0, 1],
      links: [{ event: "state", target: "inverse", action: "a" }],
    },
  };
  const inverse = {
    uid: "inverse",
    piece: "logic-not",
    position: [...support.position],
    rotation: 0,
    config: {
      mount_target: support.uid,
      mount_basis: [1, 0, 0, 0, 1, 0, 0, 0, 1],
      links: [{ event: "rising", target: support.uid, action: "release" }],
    },
  };
  p.pieces.push(memory, inverse);
  p.solution.push(structuredClone(memory), structuredClone(inverse));
  validatePuzzle(p, compatibility);
  for (
    const change of [
      (v: typeof p) => v.pieces.at(-1).config.mount_target = "missing",
      (v: typeof p) => v.pieces.at(-1).config.mount_target = "inverse",
      (v: typeof p) => v.pieces.at(-1).config.mount_target = "memory",
      (v: typeof p) =>
        v.pieces.at(-1).config.mount_basis = [2, 0, 0, 0, 1, 0, 0, 0, 1],
      (v: typeof p) =>
        v.pieces.at(-1).config.mount_basis = [-1, 0, 0, 0, 1, 0, 0, 0, 1],
      (v: typeof p) => delete v.pieces.at(-1).config.mount_basis,
      (v: typeof p) => v.pieces.at(-2).config.links[0].event = "changed",
      (v: typeof p) => v.pieces[0].config.mount_target = "memory",
    ]
  ) {
    const invalid = structuredClone(p);
    change(invalid);
    rejected(invalid);
  }
});

Deno.test("format 3 declarative guidance accepts stable targets and rejects executable or dangling fields", () => {
  const p = structuredClone(fixture);
  p.version = 3;
  p.guidance = [{kind: "attention", target: p.pieces[0].uid, connector: -1, text: "Select the release.", appear: "build", complete: "selected"}];
  validatePuzzle(p, compatibility);
  for (const change of [
    (s: Record<string, unknown>) => s.scene = "res://evil.tscn",
    (s: Record<string, unknown>) => s.target = "missing",
    (s: Record<string, unknown>) => s.connector = 999,
    (s: Record<string, unknown>) => s.complete = "script",
    (s: Record<string, unknown>) => s.position = [0, null, 0],
  ]) {
    const invalid = structuredClone(p);
    change(invalid.guidance[0]);
    rejected(invalid);
  }
  rejected({...p, version: 2});
});
