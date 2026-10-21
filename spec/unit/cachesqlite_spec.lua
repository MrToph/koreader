describe("CacheSQLite module", function()
    local CacheSQLite
    local cache

    local function testCapacity()
        it("should replace differently sized entries without losing other entries", function()
            local original = {value = "original"}
            local replacement = {value = "a longer replacement value"}
            local _, original_size = cache:insert("measure", original)
            local _, replacement_size = cache:insert("measure", replacement)
            cache:clear()
            cache.size = 2 * (original_size + replacement_size) + 1

            assert.is_true(cache:insert("other", original))
            assert.is_true(cache:insert("feed", original))
            for _ = 1, 100 do
                assert.is_true(cache:insert("feed", replacement))
                assert.are.same(replacement, cache:check("feed"))
                assert.is_true(cache:insert("feed", original))
            end
            assert.are.same(original, cache:get("other"))
            assert.are.same(original, cache:get("feed"))
        end)

        it("should evict least recently checked entries and remain usable", function()
            local UIManager = require("ui/uimanager")
            local tick = 0
            local getTime = stub(UIManager, "getTime", function()
                tick = tick + 1
                return tick
            end)
            finally(function() getTime:revert() end)

            local object = {value = "cached"}
            local _, size = cache:insert("measure", object)
            cache:clear()
            cache.size = 3 * size + 1
            for _, key in ipairs({"a", "b", "c"}) do
                assert.is_true(cache:insert(key, object))
            end
            assert.are.same(object, cache:check("a"))
            assert.is_true(cache:insert("d", object))
            assert.is_nil(cache:get("b"))
            assert.are.same(object, cache:get("a"))
            assert.are.same(object, cache:get("c"))
            assert.are.same(object, cache:get("d"))

            -- Unlike check(), get() must not refresh the entry's access time.
            assert.is_true(cache:insert("e", object))
            assert.is_nil(cache:get("c"))
            assert.are.same(object, cache:get("a"))
            assert.are.same(object, cache:get("d"))
            assert.are.same(object, cache:get("e"))
        end)
    end

    describe("CacheSQLite on disk", function()
        setup(function()
            require("commonrequire")
            CacheSQLite = require("cachesqlite")
            cache = CacheSQLite:new{
                db_path = "test.db",
                size = 1024 * 1024 * 1024,
            }
        end)
        after_each(function()
            cache:clear()
            cache.size = 1024 * 1024 * 1024
        end)

        it("should clear cache", function()
            cache:clear()
        end)

        it("should insert and get", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            local deserialized = cache:get("test")
            assert.are.same(object, deserialized)
        end)

        it("should remove object", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            cache:remove("test")
            local deserialized = cache:get("test")
            assert.is_nil(deserialized)
        end)

        it("should accept regular object", function()
            assert.is_true(cache:willAccept(100))
            cache.size = 1024
            assert.is_true(cache:insert("test", {a = 1, b = 2}))
        end)

        it("should reject giant object", function()
            assert.is_false(cache:willAccept(1024 * 1024 * 1024))
            cache.size = 10
            assert.is_false(cache:insert("test", {a = 1, b = 2}))
        end)

        testCapacity()

        it("should preserve available capacity when reopening a database", function()
            local object = {value = "cached"}
            local _, size = cache:insert("a", object)
            assert.is_true(cache:insert("b", object))
            cache = CacheSQLite:new{
                db_path = "test.db",
                size = 3 * size + 1,
            }
            assert.is_true(cache:insert("c", object))
            assert.are.same(object, cache:get("a"))
            assert.are.same(object, cache:get("b"))
            assert.are.same(object, cache:get("c"))
        end)
    end)

    describe("CacheSQLite in memory", function()
        setup(function()
            require("commonrequire")
            CacheSQLite = require("cachesqlite")
            cache = CacheSQLite:new{
                db_path = ":memory:",
                auto_close = false,
                size = 1024 * 1024 * 1024,
            }
        end)
        after_each(function()
            cache:clear()
            cache.size = 1024 * 1024 * 1024
        end)

        it("should clear cache", function()
            cache:clear()
        end)

        it("should insert and get", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            local deserialized = cache:get("test")
            assert.are.same(object, deserialized)
        end)

        it("should remove object", function()
            local object = {a = 1, b = 2}
            cache:insert("test", object)
            cache:remove("test")
            local deserialized = cache:get("test")
            assert.is_nil(deserialized)
        end)

        it("should accept regular object", function()
            assert.is_true(cache:willAccept(100))
            cache.size = 1024
            assert.is_true(cache:insert("test", {a = 1, b = 2}))
        end)

        it("should reject giant object", function()
            assert.is_false(cache:willAccept(1024 * 1024 * 1024))
            cache.size = 10
            assert.is_false(cache:insert("test", {a = 1, b = 2}))
        end)

        testCapacity()

        it("should keep connections independent between cache instances", function()
            local other
            finally(function()
                if other then other:closeDB(true) end
            end)
            other = CacheSQLite:new{
                db_path = ":memory:",
                size = 1024,
            }
            assert.is_true(cache:insert("same-key", {value = "first"}))
            assert.is_true(other:insert("same-key", {value = "second"}))
            assert.are.same({value = "first"}, cache:get("same-key"))
            assert.are.same({value = "second"}, other:get("same-key"))
            other:closeDB(true)
            assert.are.same({value = "first"}, cache:check("same-key"))
        end)

        teardown(function()
            cache:closeDB(true)
        end)
    end)
end)
