// IPC (Inter-Process Communication) for Kolos microkernel
// Message-passing based IPC for microkernel architecture
const std = @import("std");

pub const MessageType = enum(u32) {
    request,
    response,
    notification,
};

pub const MAX_MESSAGE_SIZE = 256;
pub const MAX_ENDPOINTS = 32;

// Message structure
pub const Message = struct {
    sender_id: u32,
    receiver_id: u32,
    msg_type: MessageType,
    data_len: usize,
    data: [MAX_MESSAGE_SIZE]u8,
    
    pub fn init(sender: u32, receiver: u32, msg_type: MessageType) Message {
        return Message{
            .sender_id = sender,
            .receiver_id = receiver,
            .msg_type = msg_type,
            .data_len = 0,
            .data = [_]u8{0} ** MAX_MESSAGE_SIZE,
        };
    }
    
    pub fn set_data(self: *Message, data: []const u8) !void {
        if (data.len > MAX_MESSAGE_SIZE) return error.MessageTooLarge;
        @memcpy(self.data[0..data.len], data);
        self.data_len = data.len;
    }
    
    pub fn get_data(self: *const Message) []const u8 {
        return self.data[0..self.data_len];
    }
};

// Message queue for each endpoint
const MessageQueue = struct {
    messages: [16]Message,
    read_idx: usize,
    write_idx: usize,
    count: usize,
    
    pub fn init() MessageQueue {
        return MessageQueue{
            .messages = undefined,
            .read_idx = 0,
            .write_idx = 0,
            .count = 0,
        };
    }
    
    pub fn enqueue(self: *MessageQueue, msg: Message) !void {
        if (self.count >= self.messages.len) return error.QueueFull;
        
        self.messages[self.write_idx] = msg;
        self.write_idx = (self.write_idx + 1) % self.messages.len;
        self.count += 1;
    }
    
    pub fn dequeue(self: *MessageQueue) ?Message {
        if (self.count == 0) return null;
        
        const msg = self.messages[self.read_idx];
        self.read_idx = (self.read_idx + 1) % self.messages.len;
        self.count -= 1;
        
        return msg;
    }
    
    pub fn is_empty(self: *const MessageQueue) bool {
        return self.count == 0;
    }
};

// Endpoint (port) for IPC
const Endpoint = struct {
    id: u32,
    owner_process: u32,
    queue: MessageQueue,
    active: bool,
    
    pub fn init(id: u32, process_id: u32) Endpoint {
        return Endpoint{
            .id = id,
            .owner_process = process_id,
            .queue = MessageQueue.init(),
            .active = true,
        };
    }
};

// Global IPC manager
var endpoints: [MAX_ENDPOINTS]Endpoint = undefined;
var next_endpoint_id: u32 = 1;
var allocator: ?std.mem.Allocator = null;

pub fn init(alloc: std.mem.Allocator) void {
    allocator = alloc;
}

// Create a new endpoint for a process
pub fn create_endpoint(process_id: u32) !u32 {
    if (next_endpoint_id >= MAX_ENDPOINTS) return error.TooManyEndpoints;
    
    const ep_id = next_endpoint_id;
    next_endpoint_id += 1;
    
    const ep_idx = ep_id - 1;
    endpoints[ep_idx] = Endpoint.init(ep_id, process_id);
    
    return ep_id;
}

// Send a message to an endpoint
pub fn send(msg: Message) !void {
    if (msg.receiver_id == 0 or msg.receiver_id >= next_endpoint_id) {
        return error.InvalidEndpoint;
    }
    
    const ep_idx = msg.receiver_id - 1;
    if (!endpoints[ep_idx].active) return error.EndpointNotActive;
    
    try endpoints[ep_idx].queue.enqueue(msg);
}

// Receive a message from an endpoint
pub fn receive(endpoint_id: u32) ?Message {
    if (endpoint_id == 0 or endpoint_id >= next_endpoint_id) {
        return null;
    }
    
    const ep_idx = endpoint_id - 1;
    if (!endpoints[ep_idx].active) return null;
    
    return endpoints[ep_idx].queue.dequeue();
}

// Check if endpoint has pending messages
pub fn has_messages(endpoint_id: u32) bool {
    if (endpoint_id == 0 or endpoint_id >= next_endpoint_id) {
        return false;
    }
    
    const ep_idx = endpoint_id - 1;
    if (!endpoints[ep_idx].active) return false;
    
    return !endpoints[ep_idx].queue.is_empty();
}

// Destroy an endpoint
pub fn destroy_endpoint(endpoint_id: u32) void {
    if (endpoint_id == 0 or endpoint_id >= next_endpoint_id) {
        return;
    }
    
    const ep_idx = endpoint_id - 1;
    endpoints[ep_idx].active = false;
}
