import csv
import os


def load_messages(csv_path="messages.csv"):
    """
    CSV 파일에서 메시지를 로드합니다.
    기대되는 형식: id, en, ko
    반환값:
    {
        "en": { "id_1": "text_en", ... },
        "ko": { "id_1": "text_ko", ... }
    }
    """
    messages = {"en": {}, "ko": {}}

    # 현재 파일 기준으로 절대 경로 해석
    base_dir = os.path.dirname(os.path.abspath(__file__))
    full_path = os.path.join(base_dir, csv_path)

    try:
        with open(full_path, mode='r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                msg_id = row.get("id")
                if not msg_id:
                    continue

                # 공백 문제 방지를 위해 키와 값의 앞뒤 공백 제거
                msg_id = msg_id.strip()
                messages["en"][msg_id] = row.get("en", "").strip()
                messages["ko"][msg_id] = row.get("ko", "").strip()

    except FileNotFoundError:
        print(f"Error: Could not find translation file at {full_path}")
        # Return empty structure or fallback could be implemented here
    except Exception as e:
        print(f"Error loading translations: {e}")

    return messages


MESSAGES = load_messages()
