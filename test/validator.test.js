import test from "node:test";
import assert from "node:assert/strict";
import { validateRapidCode } from "../dist/rapid-validator.js";
import { validateControllerPath } from "../dist/safety-guard.js";

test("validateRapidCode accepts balanced MODULE and PROC", () => {
  const code = `
    MODULE MainModule
      PROC main()
        TPWrite "Hello, ABB!";
      ENDPROC
    ENDMODULE
  `;
  const result = validateRapidCode(code);
  assert.equal(result.valid, true);
  assert.equal(result.errors.length, 0);
});

test("validateRapidCode supports TRAP, RECORD, and IF blocks", () => {
  const code = `
    MODULE AdvancedModule
      RECORD custom_point
        num x;
        num y;
      ENDRECORD

      TRAP err_trap
        IF TRUE THEN
          TPWrite "Error occurred";
        ENDIF
      ENDTRAP

      PROC main()
        FOR i FROM 1 TO 10 DO
          WHILE FALSE DO
            ! compact if
            IF i = 5 TPWrite "Halfway";
          ENDWHILE
        ENDFOR
      ENDPROC
    ENDMODULE
  `;
  const result = validateRapidCode(code);
  assert.equal(result.valid, true);
  assert.equal(result.errors.length, 0);
});

test("validateRapidCode detects unclosed blocks", () => {
  const brokenCode = `
    MODULE BrokenModule
      PROC main()
        IF TRUE THEN
          TPWrite "Missing ENDIF";
      ENDPROC
    ENDMODULE
  `;
  const result = validateRapidCode(brokenCode);
  assert.equal(result.valid, false);
  assert.ok(result.errors.some((e) => e.type.includes("IF")));
});

test("validateControllerPath permits safe paths and blocks directory traversal", () => {
  assert.equal(validateControllerPath("$HOME/program.mod"), "$HOME/program.mod");
  assert.equal(validateControllerPath("$TEMP/logs"), "$TEMP/logs");

  assert.throws(() => validateControllerPath("../../../etc/passwd"), /directory traversal/);
  assert.throws(() => validateControllerPath("$HOME/../system.bin"), /directory traversal/);
  assert.throws(() => validateControllerPath("$SYSTEM/secret.key"), /forbidden/);
});
