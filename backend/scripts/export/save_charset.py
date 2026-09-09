# save_charset.py
from contact_scanner_backend.model import CHARS
from contact_scanner_backend.paths import DEFAULT_CHARSET


def main():
    DEFAULT_CHARSET.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_CHARSET.write_text(CHARS, encoding="utf-8")
    print(f"Saved {DEFAULT_CHARSET}")


if __name__ == "__main__":
    main()
