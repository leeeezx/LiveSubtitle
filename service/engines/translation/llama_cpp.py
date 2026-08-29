from collections import deque
import re

import aiohttp

from .base import TranslationEngine


def _clean_translation(text: str) -> str:
    """移除模型偶尔复述的提示标签，避免它们进入浏览器字幕。"""
    cleaned = text.strip()
    cleaned = re.sub(r"^(?:当前字幕|译文|翻译结果)\s*[：:]\s*", "", cleaned)
    return cleaned.strip()


class LlamaCppEngine(TranslationEngine):
    """通过本机 llama.cpp 的 OpenAI 兼容接口调用 Hy-MT2。"""

    def __init__(self, host: str, model: str, api_key: str):
        self._host = host.rstrip("/")
        self._model = model
        self._api_key = api_key
        # 多保留一条已确认字幕，帮助处理日语跨句省略和代词指代。
        self._history: deque[tuple[str, str]] = deque(maxlen=3)

    async def translate(
        self,
        text: str,
        target_language: str,
        source_language: str = "",
    ) -> str:
        if not text:
            return ""

        previous = "\n".join(
            f"原文：{source}\n译文：{translated}"
            for source, translated in self._history
        )
        source_hint = source_language or "自动识别的语言"
        context = f"\n前文参考：\n{previous}\n" if previous else ""
        prompt = (
            f"你是视频字幕翻译器。将下面的{source_hint}字幕翻译为{target_language}。"
            "输入来自带重叠的实时语音窗口，可能从半句话开始或在句尾结束。"
            "结合前文消解省略和指代，但不得补写原文没有的信息。"
            "保持口语自然、简洁，保留人名和术语；只输出当前字幕新增内容的译文，"
            "不要解释，也不要重复输出前文。"
            f"{context}\n当前字幕：\n{text}"
        )

        timeout = aiohttp.ClientTimeout(total=30)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{self._host}/v1/chat/completions",
                headers={"Authorization": f"Bearer {self._api_key}"},
                json={
                    "model": self._model,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.1,
                    "top_p": 0.6,
                    "max_tokens": 256,
                    "stream": False,
                },
            ) as response:
                response.raise_for_status()
                data = await response.json()
                translated = _clean_translation(data["choices"][0]["message"]["content"])

        if translated:
            self._history.append((text, translated))
        return translated or text
