"""
Genie API Response Inspector
Run this to see EXACTLY what fields are in your actual API responses
"""

import os
import json
from dotenv import load_dotenv
from databricks.sdk import WorkspaceClient

load_dotenv()

def inspect_response(response, prefix=""):
    """Recursively inspect all fields in a response object"""
    inspection = {}

    # Get all attributes
    for attr in dir(response):
        # Skip private/magic methods
        if attr.startswith('_'):
            continue

        try:
            value = getattr(response, attr)

            # Skip methods
            if callable(value):
                continue

            # Get the type
            value_type = type(value).__name__

            # Store basic info
            inspection[attr] = {
                "type": value_type,
                "is_none": value is None,
                "has_value": value is not None
            }

            # If it has a value, show sample
            if value is not None:
                if isinstance(value, (str, int, float, bool)):
                    inspection[attr]["value"] = value
                elif isinstance(value, list):
                    inspection[attr]["length"] = len(value)
                    if len(value) > 0:
                        inspection[attr]["first_item_type"] = type(value[0]).__name__
                        # Recursively inspect first item if it's an object
                        if hasattr(value[0], '__dict__'):
                            inspection[attr]["first_item_fields"] = list(vars(value[0]).keys())
                else:
                    # Complex object - show its attributes
                    if hasattr(value, '__dict__'):
                        inspection[attr]["nested_fields"] = list(vars(value).keys())

        except Exception as e:
            inspection[attr] = {"error": str(e)}

    return inspection


def main():
    print("=" * 80)
    print("GENIE API RESPONSE INSPECTOR")
    print("=" * 80)
    print()

    # Get credentials
    host = os.getenv("DATABRICKS_HOST")
    token = os.getenv("DATABRICKS_TOKEN")
    space_id = os.getenv("GENIE_SPACE_ID")

    if not all([host, token, space_id]):
        print("❌ Missing credentials in .env file")
        return

    # Initialize client
    print("🔌 Connecting to Databricks...")
    client = WorkspaceClient(host=host, token=token)
    print("✅ Connected!")
    print()

    # Test query
    test_query = input("Enter a test query (or press Enter for default): ").strip()
    if not test_query:
        test_query = "Show me sample data"

    print(f"\n📤 Sending query: '{test_query}'")
    print("⏳ Waiting for response...")
    print()

    # Start conversation
    response = client.genie.start_conversation_and_wait(
        space_id=space_id,
        content=test_query
    )

    print("=" * 80)
    print("📦 GENEMESSAGE RESPONSE STRUCTURE")
    print("=" * 80)
    print()

    # Inspect top-level response
    message_inspection = inspect_response(response)
    print(json.dumps(message_inspection, indent=2))

    print()
    print("=" * 80)
    print("📎 ATTACHMENTS DETAILED INSPECTION")
    print("=" * 80)
    print()

    if response.attachments:
        for i, attachment in enumerate(response.attachments):
            print(f"\n--- Attachment {i+1} ---")
            attachment_inspection = inspect_response(attachment)
            print(json.dumps(attachment_inspection, indent=2))

            # Deep dive into query if present
            if hasattr(attachment, 'query') and attachment.query:
                print(f"\n  🔍 QUERY OBJECT DETAILS:")
                query_inspection = inspect_response(attachment.query)
                print(json.dumps(query_inspection, indent=2))

            # Deep dive into text if present
            if hasattr(attachment, 'text') and attachment.text:
                print(f"\n  📝 TEXT OBJECT DETAILS:")
                text_inspection = inspect_response(attachment.text)
                print(json.dumps(text_inspection, indent=2))

            # Deep dive into suggested_questions if present
            if hasattr(attachment, 'suggested_questions') and attachment.suggested_questions:
                print(f"\n  💡 SUGGESTED QUESTIONS DETAILS:")
                sq_inspection = inspect_response(attachment.suggested_questions)
                print(json.dumps(sq_inspection, indent=2))

            # Deep dive into query_result_metadata if present
            if hasattr(attachment, 'query_result_metadata') and attachment.query_result_metadata:
                print(f"\n  📊 QUERY RESULT METADATA DETAILS:")
                qrm_inspection = inspect_response(attachment.query_result_metadata)
                print(json.dumps(qrm_inspection, indent=2))

    # If there's a query, fetch the result data
    if response.attachments and hasattr(response.attachments[0], 'query'):
        query_attachment = response.attachments[0].query
        if query_attachment and hasattr(response.attachments[0], 'id'):
            print()
            print("=" * 80)
            print("📊 QUERY RESULT DATA STRUCTURE")
            print("=" * 80)
            print()

            try:
                result = client.genie.get_message_query_result(
                    space_id=space_id,
                    conversation_id=response.conversation_id,
                    message_id=response.id,
                    attachment_id=response.attachments[0].id
                )

                result_inspection = inspect_response(result)
                print(json.dumps(result_inspection, indent=2))

                # Deep dive into statement_response
                if hasattr(result, 'statement_response'):
                    print(f"\n  📄 STATEMENT RESPONSE DETAILS:")
                    sr_inspection = inspect_response(result.statement_response)
                    print(json.dumps(sr_inspection, indent=2))

                    # Deep dive into manifest
                    if hasattr(result.statement_response, 'manifest'):
                        print(f"\n    📋 MANIFEST DETAILS:")
                        manifest_inspection = inspect_response(result.statement_response.manifest)
                        print(json.dumps(manifest_inspection, indent=2))

                        # Schema details
                        if hasattr(result.statement_response.manifest, 'schema'):
                            print(f"\n      🗂️ SCHEMA DETAILS:")
                            schema_inspection = inspect_response(result.statement_response.manifest.schema)
                            print(json.dumps(schema_inspection, indent=2))

                    # Deep dive into result
                    if hasattr(result.statement_response, 'result'):
                        print(f"\n    📦 RESULT DATA DETAILS:")
                        result_data_inspection = inspect_response(result.statement_response.result)
                        print(json.dumps(result_data_inspection, indent=2))

            except Exception as e:
                print(f"❌ Could not fetch query results: {e}")

    print()
    print("=" * 80)
    print("✅ INSPECTION COMPLETE")
    print("=" * 80)
    print()
    print("💡 Look for fields with 'has_value: true' - those are what you can display!")
    print()


if __name__ == "__main__":
    main()
