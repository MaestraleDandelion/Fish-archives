"""用公开原文和提交历史生成正式首页数据。仅使用 Python 标准库。"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "assets" / "home-entries.js"
KINDS = {"作品": "作品讨论", "杂谈": "杂谈", "创作": "创作", "灵感": "灵感",
         "思考": "思考", "摘录": "摘录", "视频": "视频收藏"}
DATE = r"\d{4}-\d{2}-\d{2}"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8-sig")


def parse(path, raw):
    """一篇文章或季节页里的每条视频，各自对应一个稳定的列表项。"""
    kind = KINDS[path.parts[0]]
    if kind == "视频收藏":
        for part in re.split(r"(?m)^## (?!补记)", raw)[1:]:
            title, _, body = part.partition("\n")
            date = re.search(DATE, body)
            if not date:
                raise ValueError(f"{path} 的视频缺少保存日期：{title}")
            yield (title.strip(), date[0], "视频 · " + path.stem, body.strip())
    else:
        title = re.search(r"(?m)^# (.+)$", raw)[1].strip()
        work = path.parent.name if path.parts[0] == "作品" else path.parts[0]
        body = re.sub(r"(?m)^# .+\n?", "", raw, count=1).strip()
        yield (title, path.name[:10], work, body)


def history(path):
    name = path.as_posix()
    commits = git("log", "--first-parent", "--reverse", "--format=%H %cI", "HEAD", "--", name)
    previous = {}
    for line in commits.splitlines():
        rev, when = line.split()
        if not git("ls-tree", "--name-only", rev, "--", name).strip():
            previous = {}
            continue
        current = {}
        raw = git("show", f"{rev}:{name}").replace("\r\n", "\n")
        for title, date, work, body in parse(path, raw):
            key = name + ("#" + title if path.parts[0] == "视频" else "")
            if key in current:
                raise ValueError(f"{name} 中的标题重复：{title}")
            old = previous.get(key)
            events = list(old["events"]) if old else []
            if not old:
                events.append({"at": when, "kind": "新收录"})
            elif body != old["body"] or title != old["title"]:
                notes = r"(?m)^## 补记[^\n]*$"
                added = len(re.findall(notes, body)) > len(re.findall(notes, old["body"]))
                events.append({"at": when, "kind": "追加补记" if added else "正文修订"})
            current[key] = dict(id=key, title=title, work=work, kind=KINDS[path.parts[0]],
                                date=old["date"] if old else date, body=body, events=events)
        previous = current
    return list(previous.values())


def excerpt(body):
    """优先保留作者的感想或一句话，再取第一段原文。"""
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    for label in ("我的感想", "一句话", "简介"):
        for i, line in enumerate(lines):
            if line == "## " + label and i + 1 < len(lines):
                return lines[i + 1]
            if line.startswith("**" + label + "**："):
                return line.split("：", 1)[1]
    for line in lines:
        if line.startswith(("#", "<", "[!", "![")) or "｜" in line:
            continue
        text = re.sub(r"^[-*>] ", "", line).replace("**", "")
        return text if len(text) <= 90 else text[:90] + "…"
    return ""


def main():
    entries = []
    names = git("ls-tree", "-rz", "--name-only", "HEAD").split("\0")
    for name in names:
        path = Path(name)
        if not path.parts or path.parts[0] not in KINDS or path.suffix != ".md":
            continue
        if any(p.startswith(("_", ".")) or "示例" in p for p in path.parts):
            continue
        is_video = path.parts[0] == "视频" and re.fullmatch(r"\d{4}[春夏秋冬]", path.stem)
        if is_video or re.match(DATE + "_", path.name):
            entries.extend(history(path))
    cards = []
    for entry in entries:
        cards.append(dict(id=entry["id"], title=entry["title"], kind=entry["kind"],
                          date=entry["date"], updated=entry["events"][-1],
                          excerpt=excerpt(entry["body"])))
    data = json.dumps(cards, ensure_ascii=False, indent=2)
    OUTPUT.write_text("// 由 同步首页.py 生成。\nwindow.archiveEntries = " + data + ";\n", encoding="utf8")
    print(f"已同步 {len(entries)} 条正式公开内容。")


if __name__ == "__main__":
    main()
