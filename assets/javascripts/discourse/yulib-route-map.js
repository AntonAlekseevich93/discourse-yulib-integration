export default function () {
  console.log("🗺️ YuLib: Route Map is being read!"); // <--- Добавь это

  this.route("user", { path: "/u/:username" }, function () {
    this.route("preferences", function () {
      this.route("yulib", { path: "yulib" });
    });
  });
}
