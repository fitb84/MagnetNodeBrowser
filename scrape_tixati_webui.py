import requests
from bs4 import BeautifulSoup
import os

base_url = "http://localhost:8888"
output_file = os.path.expanduser(r"~/Downloads/tixati_webui_dump.html")

main_paths = [
    "/home",
    "/transfers",
    "/bandwidth",
    "/dht",
    "/settings",
    "/help"
]

session = requests.Session()

with open(output_file, "w", encoding="utf-8") as f:
    for path in main_paths:
        url = base_url + path
        resp = session.get(url)
        f.write(f"\n\n<!-- {url} -->\n")
        f.write(resp.text)

    resp = session.get(base_url + "/transfers")
    soup = BeautifulSoup(resp.text, "html.parser")
    for checkbox in soup.select("input.selection"):
        transfer_id = checkbox.get("name")
        for sub in ["details", "files", "trackers", "peers", "pieces", "bandwidth", "eventlog", "options"]:
            sub_url = f"{base_url}/transfers/{transfer_id}/{sub}"
            sub_resp = session.get(sub_url)
            f.write(f"\n\n<!-- {sub_url} -->\n")
            f.write(sub_resp.text)

print(f"All pages saved to {output_file}")
