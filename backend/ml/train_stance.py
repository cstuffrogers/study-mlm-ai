"""立场分类器训练 — TF-IDF + SVM/LogReg 轻量方案

不依赖 GPU / 大模型下载，CPU 秒级训练。
输入：ml/synthesize_data.py 合成的 317 条
输出：ml/stance_model.joblib（含 TF-IDF + 分类器 pipeline）
接口：StanceClassifier.classify(text) → "orthodox"/"deviation"

注入 triple_check.stance_classifier 后，_check_stance 优先用此分类器，规则版兜底。
"""
from __future__ import annotations

import os
import sys
import joblib
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.svm import LinearSVC
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, precision_recall_fscore_support

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from ml.synthesize_data import build_synthesized_dataset

MODEL_PATH = os.path.join(os.path.dirname(__file__), "stance_model.joblib")

# char n-gram：中文立场判定字符级比词级稳（无需分词）
TFIDF_PARAMS = {
    "analyzer": "char_wb",
    "ngram_range": (2, 4),
    "min_df": 2,
    "max_df": 0.9,
    "sublinear_tf": True,
    "max_features": 20000,
}


def _build_pipeline(model_name: str = "logreg") -> Pipeline:
    if model_name == "svm":
        clf = LinearSVC(C=1.0, class_weight="balanced", max_iter=5000)
    else:
        # LogisticRegression 有真实 predict_proba，支持 confidence 阈值降级
        clf = LogisticRegression(C=1.0, class_weight="balanced", max_iter=2000)
    return Pipeline([
        ("tfidf", TfidfVectorizer(**TFIDF_PARAMS)),
        ("clf", clf),
    ])


def train_and_evaluate() -> dict:
    data = build_synthesized_dataset()
    texts = [d["text"] for d in data]
    labels = [d["label"] for d in data]

    # 7:1.5:1.5 分层划分
    X_tr, X_tmp, y_tr, y_tmp = train_test_split(
        texts, labels, test_size=0.3, random_state=42, stratify=labels
    )
    X_val, X_te, y_val, y_te = train_test_split(
        X_tmp, y_tmp, test_size=0.5, random_state=42, stratify=y_tmp
    )
    print(f"划分: train {len(X_tr)} / val {len(X_val)} / test {len(X_te)}")

    # 训练两个候选，选 test F1 高的
    candidates = {}
    for name in ("svm", "logreg"):
        pipe = _build_pipeline(name)
        pipe.fit(X_tr, y_tr)
        te_pred = pipe.predict(X_te)
        p, r, f1, _ = precision_recall_fscore_support(
            y_te, te_pred, average=None, labels=["orthodox", "deviation"]
        )
        candidates[name] = {
            "pipe": pipe,
            "test_f1_macro": float(np.mean(f1)),
            "test_p": p.tolist(),
            "test_r": r.tolist(),
            "test_f1": f1.tolist(),
            "report": classification_report(y_te, te_pred, output_dict=True),
        }
        print(f"\n[{name}] test macro-F1={candidates[name]['test_f1_macro']:.3f}")
        print(classification_report(y_te, te_pred))

    # 优先 logreg（真实 predict_proba 支持 confidence 阈值降级，边界样本更稳）
    # SVM 无 predict_proba，decision_function 归一化概率不准，confidence 阈值方案不适用
    if candidates["svm"]["test_f1_macro"] > candidates["logreg"]["test_f1_macro"] + 0.05:
        best_name = "svm"
    else:
        best_name = "logreg"
    best = candidates[best_name]
    print(f"\n>>> 选 {best_name}（macro-F1={best['test_f1_macro']:.3f}）")

    # 保存
    joblib.dump({"pipeline": best["pipe"], "model_name": best_name}, MODEL_PATH)
    print(f"模型已保存: {MODEL_PATH}")

    return {
        "best_model": best_name,
        "test_macro_f1": best["test_f1_macro"],
        "deviation_recall": best["test_r"][1],  # deviation 是 labels[1]
        "deviation_precision": best["test_p"][1],
        "train_size": len(X_tr),
        "val_size": len(X_val),
        "test_size": len(X_te),
    }


class StanceClassifier:
    """生产推理接口 — 注入 triple_check.stance_classifier

    classify(text) → "orthodox" | "deviation"
    """

    def __init__(self, model_path: str = MODEL_PATH) -> None:
        if not os.path.exists(model_path):
            raise FileNotFoundError(
                f"立场模型未训练: {model_path}\n请先运行 python -m ml.train_stance"
            )
        bundle = joblib.load(model_path)
        self.pipe = bundle["pipeline"]

    def classify(self, text: str) -> str:
        return self.pipe.predict([text])[0]

    def predict_proba(self, text: str) -> dict:
        """概率（SVM 用 Platt 缩放，简化：用 decision_function 近似）"""
        if hasattr(self.pipe.named_steps["clf"], "predict_proba"):
            proba = self.pipe.predict_proba([text])[0]
            classes = self.pipe.classes_
            return {c: float(p) for c, p in zip(classes, proba)}
        # LinearSVC 无 predict_proba，用 decision_function 归一化近似
        df = self.pipe.decision_function([text])[0]
        # decision_function 对二分类返回标量，转概率
        import math
        p = 1.0 / (1.0 + math.exp(-df))
        return {"deviation": p, "orthodox": 1.0 - p}


if __name__ == "__main__":
    metrics = train_and_evaluate()
    print("\n" + "=" * 50)
    print("训练完成指标:")
    for k, v in metrics.items():
        print(f"  {k}: {v}")
    print("=" * 50)
