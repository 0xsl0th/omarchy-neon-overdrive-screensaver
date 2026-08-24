"use strict"

const assert = require("node:assert/strict")
const model = require("../IdleModel.js")

assert.equal(model.secondsFromConfig(12.9, 30), 12)
assert.equal(model.secondsFromConfig("0", 30), 0)
assert.equal(model.secondsFromConfig(-1, 30), 30)
assert.equal(model.secondsFromConfig("not-a-number", 30), 30)

assert.deepEqual(model.eventParts({ parse: count => ["parsed", count] }, 4), ["parsed", 4])
assert.deepEqual(model.eventParts({ data: "one,two" }, 2), ["one", "two"])

const original = { first: true }
const added = model.screensaverWindowsAfter(original, "second", true)
assert.deepEqual(added, { windows: { first: true, second: true }, count: 2 })
assert.deepEqual(original, { first: true })

const removed = model.screensaverWindowsAfter(added.windows, "first", false)
assert.deepEqual(removed, { windows: { second: true }, count: 1 })

console.log("IdleModel tests passed")
