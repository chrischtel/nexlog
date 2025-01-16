// src/analysis/patterns.zig
const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

pub const VariableRule = struct { name: []const u8, regex: []const u8, var_type: types.VarType };

pub const CategoryRule = struct {
    category: []const u8,
    keywords: []const []const u8, // Array of keywords
    threshold: usize, // Minimum keyword matches for this category
};

pub const Pattern = struct {
    template: []const u8,
    pattern_type: types.PatternType,
    metadata: types.PatternMetadata,
    variables: std.ArrayList(types.PatternVariable),
    hash: u64,
    category: []const u8,

    pub fn init(allocator: std.mem.Allocator, template: []const u8, pattern_type: types.PatternType) !*Pattern {
        // Returns *Pattern or errors.Error
        const pattern = try allocator.create(Pattern);
        pattern.* = .{
            .template = try allocator.dupe(u8, template),
            .pattern_type = pattern_type,
            .metadata = .{
                .first_seen = std.time.timestamp(),
                .last_seen = std.time.timestamp(),
                .frequency = 1,
                .confidence = 1.0,
            },
            .variables = std.ArrayList(types.PatternVariable).init(allocator),
            .hash = std.hash.Wyhash.hash(0, template),
            .category = "uncategorized",
        };
        // Detect variables after initialization
        try pattern.detectVariables(allocator, template, null);
        return pattern;
    }

    pub fn deinit(self: *Pattern, allocator: std.mem.Allocator) void {
        allocator.free(self.template);
        for (self.variables.items) |*vari| {
            for (vari.seen_values.items) |value| {
                allocator.free(value);
            }
            vari.seen_values.deinit();
        }
        self.variables.deinit();
        allocator.destroy(self);
    }

    pub fn updateMetadata(self: *Pattern) void {
        self.metadata.last_seen = std.time.timestamp();
        self.metadata.frequency += 1;
    }

    // Modified to accept variable_rules as an optional parameter
    pub fn detectVariables(self: *Pattern, allocator: std.mem.Allocator, message: []const u8, variable_rules: ?[]const VariableRule) !void {
        var words = std.mem.split(u8, message, " ");
        while (words.next()) |word| {
            var var_type: ?types.VarType = null;

            // First, try variable rules if provided
            if (variable_rules) |rules| {
                for (rules) |rule| {
                    if (matchesRegex(word, rule.regex)) {
                        var_type = rule.var_type;
                        break;
                    }
                }
            }

            // If not matched by rules, fallback to heuristic
            if (var_type == null and isVariable(word)) {
                var_type = determineVarType(word);
            }

            if (var_type) |vtype| {
                for (self.variables.items) |*vari| {
                    if (vari.var_type == vtype and std.mem.eql(u8, vari.seen_values.items[0], word)) {
                        return; // Variable already exists, skip.
                    }
                }

                var seen_values = std.ArrayList([]const u8).init(allocator);
                try seen_values.append(try allocator.dupe(u8, word));
                try self.variables.append(.{
                    .position = self.variables.items.len,
                    .var_type = vtype,
                    .seen_values = seen_values,
                });
            }
        }
    }

    fn isVariable(word: []const u8) bool {
        if (word.len == 0) return false;
        if (std.ascii.isDigit(word[0])) return true;
        var dots: u8 = 0;
        for (word) |c| {
            if (c == '.') dots += 1;
        }
        if (dots == 3) return true;
        if (std.mem.indexOf(u8, word, "@") != null) return true;
        return false;
    }

    fn determineVarType(word: []const u8) types.VarType {
        var dots: u8 = 0;
        var number_sections: u8 = 0;
        var sections = std.mem.split(u8, word, ".");
        while (sections.next()) |section| {
            dots += 1;
            if (section.len > 0 and std.ascii.isDigit(section[0])) {
                number_sections += 1;
            }
        }
        if (dots == 4 and number_sections == 4) return .ip_address;
        if (word.len > 0 and std.ascii.isDigit(word[0])) return .number;
        if (std.mem.indexOf(u8, word, "@") != null) return .email;
        return .string;
    }

    // Corrected matchesRegex function with single variable capture and manual index tracking
    fn matchesRegex(word: []const u8, regex_pattern: []const u8) bool {
        // IP regex
        if (std.mem.eql(u8, regex_pattern, "^\\d+\\.\\d+\\.\\d+\\.\\d+$")) {
            var dots: u8 = 0;
            for (word) |c| {
                if (c == '.') {
                    dots += 1;
                } else if (!std.ascii.isDigit(c)) return false;
            }
            const matched = dots == 3;
            if (matched) std.debug.print("IP matched: {s}\n", .{word});
            return matched;
        }

        // UUID regex
        if (std.mem.eql(u8, regex_pattern, "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")) {
            if (word.len != 36) return false;
            var idx: usize = 0;
            for (word) |c| {
                if (idx == 8 or idx == 13 or idx == 18 or idx == 23) {
                    if (c != '-') return false;
                } else if (!std.ascii.isHex(c)) {
                    return false;
                }
                idx += 1;
            }
            std.debug.print("UUID matched: {s}\n", .{word});
            return true;
        }

        // Number regex
        if (std.mem.eql(u8, regex_pattern, "^\\d+$")) {
            for (word) |c| {
                if (!std.ascii.isDigit(c)) return false;
            }
            std.debug.print("Number matched: {s}\n", .{word});
            return true;
        }

        // Email regex
        if (std.mem.eql(u8, regex_pattern, "^[\\w\\.]+@[\\w\\.]+$")) {
            // Simple email validation
            const at_pos = std.mem.indexOf(u8, word, "@") orelse return false;
            if (at_pos == 0 or at_pos == word.len - 1) return false;
            std.debug.print("Email matched: {s}\n", .{word});
            return true;
        }

        // Add more hardcoded patterns as needed.

        return false; // Default fallback
    }
};

pub const PatternAnalyzer = struct {
    patterns: std.AutoHashMap(u64, *Pattern),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    config: Config,

    pub const Config = struct {
        similarity_threshold: f32 = 0.85,
        max_pattern_age: i64 = 60 * 60 * 24,
        max_patterns: usize = 1000,
        variable_rules: []const VariableRule = &[_]VariableRule{},
        category_rules: []const CategoryRule = &[_]CategoryRule{},
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return .{
            .patterns = std.AutoHashMap(u64, *Pattern).init(allocator),
            .mutex = .{},
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.patterns.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.patterns.deinit();
    }

    pub fn analyzeMessage(self: *Self, message: []const u8) !?*Pattern {
        self.mutex.lock();
        defer self.mutex.unlock();

        const msg_hash = std.hash.Wyhash.hash(0, message);

        if (self.patterns.get(msg_hash)) |pattern| {
            pattern.updateMetadata();
            return pattern;
        }

        if (try self.findSimilarPattern(message)) |similar| {
            similar.updateMetadata();
            return similar;
        }

        const new_pattern = try Pattern.init(
            self.allocator,
            message,
            self.detectPatternType(message),
        );
        try new_pattern.detectVariables(self.allocator, message, self.config.variable_rules);

        // Assign category using autoCategorize method
        new_pattern.category = try self.autoCategorize(message);

        try self.patterns.put(msg_hash, new_pattern);

        try self.cleanup();

        return new_pattern;
    }
    fn cleanToken(allocator: std.mem.Allocator, token: []const u8) ![]const u8 {
        var start: usize = 0;
        var end: usize = token.len;

        // Trim leading whitespace
        while (start < end and std.ascii.isWhitespace(token[start])) {
            start += 1;
        }

        // Trim trailing punctuation
        while (end > start and !std.ascii.isAlphanumeric(token[end - 1])) {
            end -= 1;
        }

        if (end <= start) return allocator.dupe(u8, "");

        // Slice the token
        const trimmed = token[start..end];

        // Convert to lowercase
        var lower = try allocator.alloc(u8, trimmed.len);
        var idx: usize = 0; // Initialize index

        for (trimmed) |c| { // Capture only 'c'
            lower[idx] = std.ascii.toLower(c);
            idx += 1;
        }

        return lower;
    }

    fn autoCategorize(self: *PatternAnalyzer, message: []const u8) ![]const u8 {
        var tokens = std.ArrayList([]const u8).init(self.allocator);

        defer {
            for (tokens.items) |token| {
                self.allocator.free(token);
            }

            tokens.deinit();
        }
        // Tokenize message by splitting on spaces
        var iter = std.mem.split(u8, message, " ");
        while (iter.next()) |token| {
            const clean = try cleanToken(self.allocator, token);

            var is_duplicate = false;
            for (tokens.items) |existing_tokens| {
                if (std.mem.eql(u8, clean, existing_tokens)) {
                    is_duplicate = true;
                    break;
                }
            }

            if (!is_duplicate) {
                try tokens.append(clean);
            } else {
                // If duplicate, free the allocated clean token
                self.allocator.free(clean);
            }
        }

        var best_category: []const u8 = "uncategorized";
        var best_score: usize = 0;

        // Check category rules
        for (self.config.category_rules) |rule| {
            var score: usize = 0;
            for (tokens.items) |tkn| {
                for (rule.keywords) |kw| {
                    if (std.mem.eql(u8, tkn, kw)) {
                        score += 1;
                    }
                }
            }

            if (score >= rule.threshold and score > best_score) {
                best_score = score;
                best_category = rule.category;
            }
        }

        // Fallback heuristics if no category met threshold
        if (best_score == 0) {
            if (std.mem.indexOf(u8, message, "error") != null or
                std.mem.indexOf(u8, message, "fail") != null)
            {
                best_category = "error";
            }
        }

        return best_category;
    }

    fn findSimilarPattern(self: *Self, message: []const u8) !?*Pattern {
        var best_match: ?*Pattern = null;
        var best_similarity: f32 = 0;

        var it = self.patterns.iterator();
        while (it.next()) |entry| {
            const similarity = try calculateSimilarity(message, entry.value_ptr.*.template);
            if (similarity > self.config.similarity_threshold and similarity > best_similarity) {
                best_similarity = similarity;
                best_match = entry.value_ptr.*;
            }
        }

        return best_match;
    }

    fn calculateSimilarity(a: []const u8, b: []const u8) !f32 {
        // Example using Jaccard similarity instead of Levenshtein for efficiency
        return jaccardSimilarity(a, b);
    }
    /// Example similarity metric: Jaccard Similarity
    fn jaccardSimilarity(a: []const u8, b: []const u8) f32 {
        var intersection: usize = 0;
        var unions: usize = 0;

        // Convert strings to sets (unique characters)
        var set_a = std.AutoHashMap(u8, bool).init(std.heap.page_allocator);
        defer set_a.deinit();
        for (a) |c| {
            _ = set_a.put(c, true) catch {};
        }

        var set_b = std.AutoHashMap(u8, bool).init(std.heap.page_allocator);
        defer set_b.deinit();
        for (b) |c| {
            _ = set_b.put(c, true) catch {};
        }

        // Calculate intersection
        var it = set_a.iterator();
        while (it.next()) |entry| {
            if (set_b.get(entry.key_ptr.*) orelse false) {
                intersection += 1;
            }
        }

        // Calculate union
        unions = set_a.count() + set_b.count() - intersection;

        if (unions == 0) return 1.0;
        const ra: f32 = @floatFromInt(intersection);
        const rb: f32 = @floatFromInt(unions);
        return ra / rb;
    }

    fn levenshteinDistance(self: *Self, a: []const u8, b: []const u8) !usize {
        const aa: f32 = @floatFromInt(a.len);
        const max_distance: usize = @intCast(self.config.similarity_threshold * aa);
        var matrix = try std.ArrayList([]usize).initCapacity(self.allocator, a.len + 1);
        defer matrix.deinit();

        for (0..a.len + 1) |i| {
            var row = try self.allocator.alloc(usize, b.len + 1);
            try matrix.append(row);
            row[0] = i;
        }

        for (0..b.len + 1) |j| {
            matrix.items[0][j] = j;
        }

        for (1..a.len + 1) |i| {
            for (1..b.len + 1) |j| {
                const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
                matrix.items[i][j] = @min(
                    matrix.items[i - 1][j] + 1,
                    @min(
                        matrix.items[i][j - 1] + 1,
                        matrix.items[i - 1][j - 1] + cost,
                    ),
                );

                // Early termination if distance exceeds max_distance
                if (matrix.items[i][j] > max_distance) {
                    return max_distance;
                }
            }
        }

        const result = matrix.items[a.len][b.len];

        for (matrix.items) |row| {
            self.allocator.free(row);
        }

        return result;
    }

    fn detectPatternType(self: *Self, message: []const u8) types.PatternType {
        _ = self;
        if (std.mem.startsWith(u8, message, "CUSTOM_TYPE:")) {
            return .custom;
        }
        if (std.mem.indexOf(u8, message, "error") != null or
            std.mem.indexOf(u8, message, "fail") != null)
        {
            return .err;
        }
        if (std.mem.indexOf(u8, message, "metric") != null or
            std.mem.indexOf(u8, message, "measure") != null)
        {
            return .metric;
        }
        if (std.mem.indexOf(u8, message, "event") != null) {
            return .event;
        }
        return .message;
    }

    fn cleanup(self: *Self) !void {
        const now = std.time.timestamp();
        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        var it = self.patterns.iterator();
        while (it.next()) |entry| {
            if (now - entry.value_ptr.*.metadata.last_seen > self.config.max_pattern_age) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        if (self.patterns.count() > self.config.max_patterns) {
            var patterns = std.ArrayList(PatternInfo).init(self.allocator);
            defer patterns.deinit();

            it = self.patterns.iterator();
            while (it.next()) |entry| {
                try patterns.append(.{
                    .hash = entry.key_ptr.*,
                    .last_seen = entry.value_ptr.*.metadata.last_seen,
                });
            }

            std.mem.sort(PatternInfo, patterns.items, {}, struct {
                pub fn lessThan(_: void, a: PatternInfo, b: PatternInfo) bool {
                    return a.last_seen < b.last_seen;
                }
            }.lessThan);

            const remove_count = self.patterns.count() - self.config.max_patterns;
            for (patterns.items[0..remove_count]) |pattern| {
                try to_remove.append(pattern.hash);
            }
        }

        for (to_remove.items) |hash| {
            if (self.patterns.fetchRemove(hash)) |kv| {
                kv.value.deinit(self.allocator);
            }
        }
    }

    const PatternInfo = struct { hash: u64, last_seen: i64 };

    pub fn getPatternCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.patterns.count();
    }
};
