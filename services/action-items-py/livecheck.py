"""Live check for the OpenAI extraction path (skips S3 and Temporal).

    AWS_PROFILE=... AWS_REGION=us-east-1 \
    OPENAI_SECRET_ID=arp/openai-api-key \
    python livecheck.py
"""

import os

from activities import ActionItemsActivities, resolve_api_key

SAMPLE = (
    "spk_0: Morning everyone. We need to decide on the launch date. "
    "spk_1: I think Friday works if QA signs off. "
    "spk_0: Agreed, let's target Friday. Bob, can you own the release notes? "
    "spk_1: Yes, I'll have them ready Thursday. Also someone needs to email the customer. "
    "spk_0: I'll take the customer email."
)


def main() -> None:
    activities = ActionItemsActivities(
        api_key=resolve_api_key(),
        model=os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
        base_url=os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"),
    )
    items = activities.extract_items(SAMPLE)
    print(f"extracted {len(items)} action item(s):")
    for i, item in enumerate(items, 1):
        print(f"  {i}. {item}")


if __name__ == "__main__":
    main()
