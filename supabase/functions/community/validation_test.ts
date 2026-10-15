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
Deno.test("catalog, versions, scene paths and impersonated registration are rejected", () => {
  rejected(fixture, "unknown");
  for (
    const [field, value] of [
      ["version", 3],
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
