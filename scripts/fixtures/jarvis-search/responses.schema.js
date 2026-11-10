// The request/response contract excerpt is code, not a byte fixture.
"use strict";
module.exports = {
  "source": {
    "guide": "https://developers.openai.com/api/docs/guides/tools-web-search",
    "request": "https://developers.openai.com/api/reference/resources/responses/methods/create",
    "read": "2026-11-10",
    "operation": "POST /v1/responses"
  },
  "rule": [
    "Keep the request fields the executor sends and the response fields it consumes.",
    "The output branches keep web_search_call, message, output_text and url_citation from the guide's example.",
    "The request excerpt narrows tool and include choices to this integration. Other response metadata is omitted, not synthesized."
  ],
  "omitted": ["Other tools, reasoning output items, response metadata, streaming events and unused usage details."],
  "schemas": {
    "Request": {
      "type": "object",
      "properties": {
        "model": {"type": "string"},
        "service_tier": {"enum": ["default"]},
        "input": {"type": "string"},
        "tools": {"type": "array", "items": {"type": "object", "properties": {"type": {"enum": ["web_search"]}}, "required": ["type"]}},
        "tool_choice": {"enum": ["required"]},
        "max_tool_calls": {"type": "integer"},
        "parallel_tool_calls": {"type": "boolean"},
        "max_output_tokens": {"type": "integer"},
        "include": {"type": "array", "items": {"enum": ["web_search_call.action.sources"]}},
        "store": {"type": "boolean"}
      },
      "required": ["model", "input", "tools"]
    },
    "Response": {
      "type": "object",
      "properties": {
        "status": {"enum": ["completed"]},
        "service_tier": {"enum": ["default", "priority"]},
        "tool_usage": {
          "type": "object",
          "properties": {
            "web_search": {
              "type": "object",
              "properties": {"num_requests": {"type": "integer"}},
              "required": ["num_requests"]
            }
          },
          "required": ["web_search"]
        },
        "usage": {
          "type": "object",
          "properties": {
            "input_tokens": {"type": "integer"},
            "output_tokens": {"type": "integer"},
            "input_tokens_details": {"type": "object", "properties": {"cached_tokens": {"type": "integer"}}}
          },
          "required": ["input_tokens", "output_tokens"]
        },
        "output": {
          "type": "array",
          "items": {
            "oneOf": [
              {
                "type": "object",
                "properties": {
                  "type": {"enum": ["web_search_call"]},
                  "status": {"enum": ["completed"]},
                  "action": {
                    "type": "object",
                    "properties": {
                      "type": {"enum": ["search"]},
                      "sources": {"type": "array", "items": {"type": "object", "properties": {"type": {"enum": ["url"]}, "url": {"type": "string"}}, "required": ["type", "url"]}}
                    },
                    "required": ["type"]
                  }
                },
                "required": ["type", "status", "action"]
              },
              {
                "type": "object",
                "properties": {
                  "type": {"enum": ["message"]},
                  "content": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "type": {"enum": ["output_text"]},
                        "text": {"type": "string"},
                        "annotations": {
                          "type": "array",
                          "items": {
                            "type": "object",
                            "properties": {
                              "type": {"enum": ["url_citation"]},
                              "title": {"type": "string"},
                              "url": {"type": "string"},
                              "start_index": {"type": "integer"},
                              "end_index": {"type": "integer"}
                            },
                            "required": ["type", "title", "url", "start_index", "end_index"]
                          }
                        }
                      },
                      "required": ["type", "text", "annotations"]
                    }
                  }
                },
                "required": ["type", "content"]
              }
            ]
          }
        }
      },
      "required": ["status", "output"]
    }
  }
};
