const std = @import("std");
const stdout = std.io.getStdOut().writer();

const Base64 = struct {
    _table: *const [64]u8,

    // Constructor for 'Base64' struct.
    pub fn init() Base64 {
        const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const lower = "abcdefghijklmnopqrstuvwxyz";
        const numbers_symb = "0123456789+/";
        return Base64{
            ._table = upper ++ lower ++ numbers_symb,
        };
    }

    // Returns char at 'index' argmument in the Base64 table.
    fn _char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    // Returns the index of the 'char' argmument in the Base64 table.
    fn _char_index(self: Base64, char: u8) u8 {
        if (char == '=') {
            return 64;
        }
        var index: u8 = 0;
        for (0..63) |i| {
            if (self._char_at(i) == char)
                break;
            index += 1;
        }

        return index;
    }

    fn encode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) {
            return "";
        }

        const n_out = try _calc_encode_length(input);
        var out = try allocator.alloc(u8, n_out);
        var buf = [3]u8{ 0, 0, 0 };
        var count: u8 = 0;
        var iout: u64 = 0;

        // Iterates over indecies of 'input' array.
        for (input, 0..) |_, i| {
            // For each iteration, the next index of 'input' is added to the next index of 'buf'.
            buf[count] = input[i];
            count += 1;

            // QUESTION: Would it be better to load all 3 elements from the
            // current group from 'input' at one time, instead of iterating
            // over each element one-by-one?

            // // My personal optimization (WIP)
            // // When length of 'buf' is equal to 1
            // if (count == 1) {
            //     // Assigns value for current (4 element) output group.
            //     out[iout] = self._char_at(buf[0] >> 2);
            // }
            // out[iout + 1] = self._char_at((buf[0] & 0x03) << 4);
            // out[iout + 2] = '=';
            // out[iout + 3] = '=';
            //
            // // When length of 'buf' is equal to 2
            // if (count == 2) {
            //     // Reassigns values of indexes '1' and '2'
            //     // of the current (4 element) 6-bit output group
            //     out[iout + 1] = self._char_at(((buf[0] & 0x03) << 4) + (buf[1] >> 4));
            //     out[iout + 2] = self._char_at((buf[1] & 0x0f) << 2);
            // }
            //
            // // When length of 'buf' is equal to 3
            // if (count == 3) {
            //     // Reassigns values of indexes '2' and '3'
            //     // of the current (4 element) 6-bit output group
            //     out[iout + 2] = self._char_at(((buf[1] & 0x0f) << 2) + (buf[2] >> 6));
            //     out[iout + 3] = self._char_at(buf[2] & 0x3f);
            //     // Moves output indext to next grouping of 4 6-bit elements
            //     iout += 4;
            //     count = 0;
            //     // QUESTION: Should the buffer also be cleared? Or is this not
            //     // necessary because each branch only addresses the current or
            //     // previous elements, but never the next?
            // }

            // ORIGINAL
            if (count == 3) {
                out[iout] = self._char_at(buf[0] >> 2);
                out[iout + 1] = self._char_at(((buf[0] & 0x03) << 4) + (buf[1] >> 4));
                out[iout + 2] = self._char_at(((buf[1] & 0x0f) << 2) + (buf[2] >> 6));
                out[iout + 3] = self._char_at(buf[2] & 0x3f);
                iout += 4;
                count = 0;
            }
        }

        if (count == 1) {
            out[iout] = self._char_at(buf[0] >> 2);
            out[iout + 1] = self._char_at((buf[0] & 0x03) << 4);
            out[iout + 2] = '=';
            out[iout + 3] = '=';
        }

        if (count == 2) {
            out[iout] = self._char_at(buf[0] >> 2);
            out[iout + 1] = self._char_at(((buf[0] & 0x03) << 4) + (buf[1] >> 4));
            out[iout + 2] = self._char_at((buf[1] & 0x0f) << 2);
            out[iout + 3] = '=';
            // TODO: Figure out why when the count is only '2', the
            // function moves onto the next output grouping of 4.
            iout += 4;
        }

        return out;
    }

    fn decode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) {
            return "";
        }

        const n_output = try _calc_decode_length(input);
        var output = try allocator.alloc(u8, n_output);
        var count: u8 = 0;
        var iout: u64 = 0;
        var buf = [4]u8{ 0, 0, 0, 0 };

        // Iterate over element of 'input' array.
        for (0..input.len) |i| {
            // Assign current element of 'input' array to 'buf'.
            buf[count] = self._char_index(input[i]);
            count += 1;
            // Skip to next iteration if 'buf' does not have 4 current elements
            if (count == 4) {
                output[iout] = (buf[0] << 2) + (buf[1] >> 4);
                if (buf[2] != 64) {
                    output[iout + 1] = (buf[1] << 4) + (buf[2] >> 2);
                }
                if (buf[3] != 64) {
                    output[iout + 2] = (buf[2] << 6) + buf[3];
                }
                iout += 3;
                count = 0;
            }
        }

        return output;
    }
};

fn _calc_encode_length(input: []const u8) !usize {
    if (input.len < 3) {
        return 4;
    }

    const n_groups: usize = try std.math.divCeil(usize, input.len, 3);

    return n_groups * 4;
}

fn _calc_decode_length(input: []const u8) !usize {
    if (input.len < 4) {
        return 3;
    }

    const n_groups: usize = try std.math.divFloor(usize, input.len, 4);
    var multiple_groups: usize = n_groups * 3;

    var i: usize = input.len - 1;
    while (i > 0) : (i -= 1) {
        if (input[i] == '=') {
            multiple_groups -= 1;
        } else {
            break;
        }
    }

    return multiple_groups;
}

pub fn main() !void {
    var memory_buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&memory_buffer);
    const allocator = fba.allocator();

    const text = "Testing some more stuff";
    const etext = "VGVzdGluZyBzb21lIG1vcmUgc3R1ZmY=";

    const base64 = Base64.init();
    const encoded_text = try base64.encode(allocator, text);
    const decoded_text = try base64.decode(allocator, etext);

    try stdout.print("Encoded text: {s}\n", .{encoded_text});
    try stdout.print("   Expecting: {s}\n\n", .{etext});
    try stdout.print("Decoded text: {s}\n", .{decoded_text});
    try stdout.print("   Expecting: {s}\n", .{text});
}
