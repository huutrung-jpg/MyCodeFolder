# modules/main.py
import os
import json
import shutil

# --- Khởi tạo các đường dẫn lưu data ---
DATA_DIR       = os.path.join(os.getcwd(), "data")
WF_DIR         = os.path.join(os.getcwd(), "workflows")
WORKFLOW_DIR   = os.path.join(DATA_DIR, "workflows")
CONFIG_FILE    = os.path.join(DATA_DIR, "config.json")
ORDER_FILE     = os.path.join(DATA_DIR, "order.json")

def ensure_dirs():
    # Tạo cả thư mục data và workflows nếu chưa có
    os.makedirs(WORKFLOW_DIR, exist_ok=True)
    # tạo luôn file order.json nếu chưa có
    os.makedirs(DATA_DIR, exist_ok=True)
    if not os.path.exists(ORDER_FILE):
        save_order([])

def load_config_data():
    default = {
        "WAIT_GEN_VIDEO": 10,
        "WAIT_GEN_IMAGE": 5,
        "WAIT_IF_ERROR": 9999,
        "WAIT_DOW_VIDEO": 5,
        "WAIT_RESEND_VIDEO": 30,
        "WAIT_RESEND_IMAGE": 30,
        "WAIT_RANDOM_VIDEO": 20,
        "WAIT_RANDOM_IMAGE": 20,
        "NUMBER_REQUEST_DOW": "10",
        "SHORT_WORKFLOW_NAME": "W",
        "SHORT_VIDEO_NAME": "V",
        "SHORT_IMAGE_NAME": "I",
        "cs_mode_resume": "ask",
        "cs_mode_download_res": "720"
    }
    # Nếu chưa có file config thì khởi tạo
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            for k, v in default.items():
                data.setdefault(k, v)
            return data
        except:
            pass
    # Tạo mới file config
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(default, f, indent=4, ensure_ascii=False)
    return default

def save_config_data(cfg):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=4, ensure_ascii=False)

def load_order():
    try:
        with open(ORDER_FILE, "r", encoding="utf-8") as f:
            lst = json.load(f)
        return [fn for fn in lst if os.path.exists(os.path.join(WORKFLOW_DIR, fn))]
    except:
        return []

def save_order(lst):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(ORDER_FILE, "w", encoding="utf-8") as f:
        json.dump(lst, f, indent=4, ensure_ascii=False)


def load_cookie_data(profile):
    COOKIE_FILE = os.path.join(DATA_DIR, f"web_cookies_{profile}.json")
    if not os.path.exists(COOKIE_FILE):
        return ""
    try:
        with open(COOKIE_FILE, "r", encoding="utf-8") as f:
            return f.read()
    except:
        return ""

def save_cookie_data(text, profile):
    os.makedirs(DATA_DIR, exist_ok=True)
    COOKIE_FILE = os.path.join(DATA_DIR, f"web_cookies_{profile}.json")
    with open(COOKIE_FILE, "w", encoding="utf-8") as f:
        f.write(text)

def list_workflows():
    """
    Trả về danh sách workflows theo thứ tự trong order.json.
    Nếu file mới, sẽ khởi tạo order dựa trên sort().
    """
    ensure_dirs()
    files = [f for f in os.listdir(WORKFLOW_DIR) if f.lower().endswith(".json")]
    order = load_order()
    ordered = [f for f in order if f in files]
    extras = sorted([f for f in files if f not in ordered])
    full = ordered + extras         # <— sửa ở đây
    save_order(full)
    return full


def load_workflow_data(filename):
    path = os.path.join(WORKFLOW_DIR, filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)
    # nếu filename chưa nằm trong order thì thêm vào cuối
    order = load_order()
    if filename not in order:
        order.append(filename)
        save_order(order)

def save_workflow_data(filename, data):
    ensure_dirs()
    path = os.path.join(WORKFLOW_DIR, filename)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)

def delete_workflow(filename: str):
    """
    Xóa file workflow và cập nhật order.json.
    """
    ensure_dirs()
    path = os.path.join(WORKFLOW_DIR, filename)
    if os.path.exists(path):
        os.remove(path)
    
    # 2. Xóa thư mục cùng tên trong WF_DIR
    folder_name = os.path.splitext(filename)[0]
    folder_path = os.path.join(WF_DIR, folder_name)
    if os.path.isdir(folder_path):
        shutil.rmtree(folder_path, ignore_errors=True)

    # Cập nhật order.json: bỏ filename khỏi list
    order = load_order()
    if filename in order:
        order.remove(filename)
        save_order(order)
        
def join_chars_he():
    letters = ["H","e","l","i","a","i",".","n","e","t"]
    return "".join(letters)