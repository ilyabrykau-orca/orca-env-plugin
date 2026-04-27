#!/usr/bin/env python3
"""Minimal MCP JSON-RPC stub for serena. Returns STUB_SERENA_RESULT for all tool calls."""
import json, sys

TOOLS = [
    {"name": "activate_project", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "find_symbol", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "get_symbols_overview", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "find_referencing_symbols", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "replace_symbol_body", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "replace_content", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "insert_after_symbol", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "insert_before_symbol", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "rename_symbol", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "safe_delete_symbol", "description": "stub", "inputSchema": {"type": "object", "properties": {}}},
]

def handle(req):
    method = req.get("method", "")
    rid = req.get("id")
    if method == "initialize":
        return {"jsonrpc":"2.0","id":rid,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"serena-stub","version":"0.0.1"}}}
    if method == "tools/list":
        return {"jsonrpc":"2.0","id":rid,"result":{"tools": TOOLS}}
    if method == "tools/call":
        name = req.get("params",{}).get("name","")
        return {"jsonrpc":"2.0","id":rid,"result":{"content":[{"type":"text","text":f"STUB_SERENA_RESULT for {name}"}]}}
    if method == "notifications/initialized":
        return None
    return {"jsonrpc":"2.0","id":rid,"error":{"code":-32601,"message":"method not found"}}

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
        resp = handle(req)
        if resp:
            print(json.dumps(resp), flush=True)
    except Exception as e:
        print(json.dumps({"jsonrpc":"2.0","id":None,"error":{"code":-32700,"message":str(e)}}), flush=True)
