# 04: Docs amendment

**What to build:** The agent docs teach ADR 0167, not the old Tool Tiers.
The readability doc's Tool Tiers section becomes a pointer to the Tool
Reference and ADR 0167, the "merge consecutive jq reads" rule is removed,
the Readability Lint rule table lists the new rules, and the scope reads
"all tracked code". The comment style doc adds the required "what" comment
above every jq/awk/sed program and 2-pipe pipeline. The `CONTEXT.md`
Readability Lint entry names the new rules' purpose. Coding standards
point at the Tool Reference.

**Blocked by:** 02, 03

**Status:** done

- [x] Readability doc: Tool Tiers replaced, jq-merge rule gone, rule table
      current, scope widened
- [x] Comment style doc: "what" comment rule added
- [x] `CONTEXT.md` Readability Lint entry updated
- [x] Coding standards link the Tool Reference
- [x] Readability Lint (ADR links, doc paths) passes
