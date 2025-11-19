# get_cookie.py
from run_cookie import init_driver, export_auth_state, ask_profile_name
import sys

if __name__ == "__main__":
    if len(sys.argv) >= 2:
        profile_name = sys.argv[1].strip()
    else:
        profile_name = ask_profile_name()

    drv = init_driver(profile_name)  # <-- gọi đúng lúc
    try:
        export_auth_state(drv, profile_name)
    finally:
        drv.quit()
