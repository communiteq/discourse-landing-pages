import { click, visit, waitFor } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

acceptance("Global | JSON editor", function (needs) {
  needs.user();

  let savedGlobal;

  needs.pretender((server, helper) => {
    server.get("/admin/plugins/discourse-landing-pages.json", () => {
      return helper.response({ name: "name", description: "description" });
    });
    server.get("/landing/page", () => {
      return helper.response({
        pages: [{ id: "page_0", name: "test", path: "test" }],
        menus: [],
        remote: null,
        global: {
          scripts: [],
          header: { original: true },
          footer: { original: true },
        },
      });
    });
    server.put("/landing/global", (request) => {
      savedGlobal = new URLSearchParams(request.requestBody);
      return helper.response({ success: true });
    });
  });

  test("renders JSON editors", async function (assert) {
    await visit("/admin/plugins/discourse-landing-pages/main");
    await click("button.global");
    await waitFor(".global-editor .ace_editor");

    assert.dom(".global-editor .ace_editor").exists({ count: 2 });
  });

  test("editing and saving JSON persists the edited values", async function (assert) {
    await visit("/admin/plugins/discourse-landing-pages/main");
    await click("button.global");
    await waitFor(".global-editor .ace_editor");

    const editors = document.querySelectorAll(".global-editor .ace_editor");
    editors[0].aceEditor.setValue('{"editedHeader":true}');
    editors[1].aceEditor.setValue('{"editedFooter":true}');
    await click(".page-header .btn-primary");

    assert.strictEqual(savedGlobal.get("global[header][editedHeader]"), "true");
    assert.strictEqual(savedGlobal.get("global[footer][editedFooter]"), "true");
    assert.notOk(savedGlobal.has("global[header][original]"));
  });

  test("invalid edited JSON displays a validation error", async function (assert) {
    savedGlobal = undefined;
    await visit("/admin/plugins/discourse-landing-pages/main");
    await click("button.global");
    await waitFor(".global-editor .ace_editor");

    const editor = document.querySelector(".global-editor .ace_editor");
    editor.aceEditor.setValue("invalidjson");
    await click(".page-header .btn-primary");

    assert.dom(".global-editor .validation-error").exists({ count: 1 });
    assert.strictEqual(savedGlobal, undefined, "invalid JSON is not submitted");
  });
});
