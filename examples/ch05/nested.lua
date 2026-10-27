-- Tables nest: a value can be another table.
local book = {
  title = "Programming in Lua",
  authors = { "Roberto Ierusalimschy" },
  edition = { number = 4, year = 2016 },
}
print(book.title, book.authors[1], book.edition.year)

-- A matrix is an array of arrays.
local grid = {
  { 1, 2, 3 },
  { 4, 5, 6 },
}
print(grid[2][3], #grid, #grid[1])

-- Constructors can mix array items and named fields.
-- Trailing commas are fine; ; works as a separator too.
local mixed = { "a", "b", n = 2; [10] = "x", }
print(mixed[1], mixed[2], mixed.n, mixed[10], #mixed)

-- Indexing a missing nested table is an error. (pcall: Chapter 9.)
print(pcall(function() return book.publisher.name end))
