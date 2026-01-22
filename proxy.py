import socket
import threading
import hashlib
import base64

HOST = 'localhost'
PORT1 = 7424
PORT2 = 5000

def parse_websocket_frame(data):
    if len(data) < 2:
        return None, data
    byte1 = data[0]
    fin = (byte1 & 0x80) != 0
    opcode = byte1 & 0x0F
    byte2 = data[1]
    mask = (byte2 & 0x80) != 0
    length = byte2 & 0x7F
    offset = 2
    if length == 126:
        if len(data) < offset + 2:
            return None, data
        length = int.from_bytes(data[offset:offset+2], 'big')
        offset += 2
    elif length == 127:
        if len(data) < offset + 8:
            return None, data
        length = int.from_bytes(data[offset:offset+8], 'big')
        offset += 8
    if mask:
        if len(data) < offset + 4:
            return None, data
        mask_key = data[offset:offset+4]
        offset += 4
    else:
        mask_key = None
    if len(data) < offset + length:
        return None, data
    payload = data[offset:offset+length]
    if mask:
        payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
    return payload, data[offset+length:]

def create_websocket_frame(message):
    payload = message.encode('utf-8')
    length = len(payload)
    frame = bytearray()
    frame.append(0x81)  # FIN=1, opcode=1 (text)
    if length < 126:
        frame.append(length)
    elif length < 65536:
        frame.append(126)
        frame.extend(length.to_bytes(2, 'big'))
    else:
        frame.append(127)
        frame.extend(length.to_bytes(8, 'big'))
    frame.extend(payload)
    return bytes(frame)

def handle_plain_to_ws(client_socket, other_client):
    while True:
        try:
            data = client_socket.recv(1024)
            if not data:
                break
            message = data.decode('utf-8', errors='ignore')
            print(f"Server1 to Server2: {message}")
            frame = create_websocket_frame(message)
            other_client.sendall(frame)
        except:
            break

def handle_ws_to_plain(client_socket, other_client):
    buffer = b''
    while True:
        try:
            data = client_socket.recv(1024)
            if not data:
                break
            buffer += data
            while True:
                payload, remaining = parse_websocket_frame(buffer)
                if payload is None:
                    break
                buffer = remaining
                message = payload.decode('utf-8', errors='ignore')
                print(f"Server2 to Server1: {message}")
                encoded = message.encode('utf-8')
                other_client.sendall(encoded)
        except:
            break

# Create server sockets
server1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server1.bind((HOST, PORT1))
server1.listen(1)

server2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server2.bind((HOST, PORT2))
server2.listen(1)

print("Waiting for connections on ports 5000 and 5001...")

conn1, addr1 = server1.accept()

conn2, addr2 = server2.accept()

# WebSocket handshake for port 5001
request = conn2.recv(1024).decode('utf-8')
if 'upgrade: websocket' in request.lower():
    lines = request.split('\r\n')
    key = None
    for line in lines:
        if line.lower().startswith('sec-websocket-key:'):
            key = line.split(': ', 1)[1]
            break
    if key:
        magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        accept = base64.b64encode(hashlib.sha1((key + magic).encode('utf-8')).digest()).decode('utf-8')
        response = f"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n"
        conn2.sendall(response.encode('utf-8'))
        print("WebSocket handshake completed for port 5001")
    else:
        print("Invalid WebSocket request")
        conn2.close()
        exit(1)
else:
    print("Not a WebSocket upgrade request")
    conn2.close()
    exit(1)

# Start threads for bidirectional message forwarding
threading.Thread(target=handle_plain_to_ws, args=(conn1, conn2)).start()
threading.Thread(target=handle_ws_to_plain, args=(conn2, conn1)).start()

print("Message forwarding active. Send messages to one port to receive on the other.")
