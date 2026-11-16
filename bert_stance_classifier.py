#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
正统马克思主义立场分类器训练Pipeline
======================================
目标：判断一段文本的哲学立场是"正统"还是"偏离"

训练数据构成：
- 正样本(orthodox)：教科书原文、马恩列斯毛原著、官方阐释
- 负样本(deviation)：西马著作摘录、后现代马克思主义、明显反马克思主义
- 困难负样本(hard_negative)：似是而非的表述（如强调主体性但否定反映论）

模型架构：
- 基座：bert-base-chinese / macbert-large
- 分类头：Dropout + Linear(768→3)  [orthodox, deviation, neutral]
- 损失：Focal Loss（处理类别不平衡）

精度目标：
- 准确率(Accuracy) > 98%
- 精确率(Precision) > 99%（对deviation类）
- 召回率(Recall) > 97%（对deviation类）
"""

import os
import json
import random
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, precision_recall_fscore_support
from collections import Counter
import warnings
warnings.filterwarnings('ignore')

# ============================================================
# 1. 配置与随机种子
# ============================================================

class Config:
    # 模型配置
    model_name = "bert-base-chinese"  # 或 "hfl/chinese-macbert-large"
    max_length = 256
    num_classes = 3  # orthodox, deviation, neutral
    hidden_dropout_prob = 0.3

    # 训练配置
    batch_size = 32
    learning_rate = 2e-5
    weight_decay = 0.01
    epochs = 10
    warmup_ratio = 0.1
    grad_clip = 1.0

    # 路径配置
    data_path = "./stance_train_data.json"
    output_dir = "./stance_model_output"
    best_model_path = os.path.join(output_dir, "best_model.pt")

    # 设备
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    # Focal Loss
    focal_alpha = [0.3, 0.5, 0.2]  # 类别权重 [neutral, orthodox, deviation]
    focal_gamma = 2.0

# 设置随机种子
def set_seed(seed=42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)

set_seed(42)

# ============================================================
# 2. 训练数据构建（专家标注数据集）
# ============================================================

# 这里内嵌一个最小可运行的数据集示例
# 实际生产环境应从数据库/文件加载，由马哲专家团队标注

def build_seed_dataset():
    """
    构建种子训练数据集
    label: 0=neutral, 1=orthodox, 2=deviation
    """
    data = []

    # ===== 正样本：正统(orthodox) =====
    orthodox_samples = [
        "物质是标志客观实在的哲学范畴，这种客观实在是人通过感觉感知的。",
        "实践是人类能动地改造世界的社会性的物质活动。",
        "社会存在决定社会意识，社会意识对社会存在具有反作用。",
        "矛盾存在于一切事物的发展过程中，矛盾双方既对立又统一。",
        "认识来源于实践，实践是检验真理的唯一标准。",
        "生产力决定生产关系，生产关系对生产力具有反作用。",
        "经济基础决定上层建筑，上层建筑对经济基础具有反作用。",
        "阶级斗争是阶级社会发展的直接动力。",
        "人民群众是历史的创造者。",
        "真理是标志主观与客观相符合的哲学范畴。",
        "旧唯物主义的立脚点是市民社会，新唯物主义的立脚点则是人类社会。",
        "不是人们的意识决定人们的存在，相反，是人们的社会存在决定人们的意识。",
        "辩证法三大规律：对立统一规律、质量互变规律、否定之否定规律。",
        "认识的辩证运动过程是：实践—认识—再实践—再认识。",
        "马克思主义哲学是科学的世界观和方法论。",
        "物质第一性，意识第二性，这是唯物主义的基本立场。",
        "世界的真正统一性在于它的物质性。",
        "运动是物质的根本属性和存在方式。",
        "时间和空间是物质运动的存在形式。",
        "意识是人脑的机能，是客观存在的主观映象。",
        "对立统一规律是唯物辩证法的实质和核心。",
        "矛盾的普遍性和特殊性的关系是矛盾问题的精髓。",
        "主要矛盾在矛盾体系中处于支配地位，对事物发展起决定作用。",
        "量变是质变的必要准备，质变是量变的必然结果。",
        "否定之否定规律揭示了事物发展的前进性与曲折性的统一。",
        "感性认识包括感觉、知觉和表象三种形式。",
        "理性认识包括概念、判断和推理三种形式。",
        "感性认识和理性认识是辩证统一的，理性认识依赖于感性认识。",
        "真理具有客观性、绝对性和相对性。",
        "价值是揭示外部客观世界对于满足人的需要的意义关系的范畴。",
        "生产方式是生产力和生产关系的统一。",
        "商品是使用价值和价值的矛盾统一体。",
        "劳动二重性决定商品二因素。",
        "剩余价值是由雇佣工人创造的被资本家无偿占有的超过劳动力价值的价值。",
        "资本是能够带来剩余价值的价值。",
        "帝国主义是资本主义的垄断阶段。",
        "社会主义必然代替资本主义，这是不以人的意志为转移的客观规律。",
        "无产阶级专政是达到消灭一切阶级差别的过渡。",
        "马克思主义政党是工人阶级的先锋队。",
        "实现共产主义是马克思主义最崇高的社会理想。",
    ]

    # ===== 负样本：偏离(deviation) =====
    deviation_samples = [
        "辩证法只存在于主体与客体的相互作用中，自然界本身不存在辩证法。",
        "自然辩证法是恩格斯对马克思思想的歪曲，马克思从未承认自然辩证法。",
        "物化不仅是商品拜物教，更是资本主义社会中人的全部生存结构的异化。",
        "无产阶级在发达工业社会中已被整合进体制，丧失了革命主体性。",
        "历史不是由经济决定的线性过程，而是由政治、意识形态、理论等多种因素复杂地共同决定的。",
        "经济基础决定上层建筑是一种经济本质主义，必须被解构。",
        "不存在统一的无产阶级主体，革命主体是多元的、分散的、通过话语建构的民众。",
        "马克思主义仍停留在生产逻辑中，没有真正超越资本主义。",
        "真理不是对客观实在的反映，而是话语建构的产物。",
        "社会存在和社会意识是相互决定的，不存在单向的决定关系。",
        "物质概念是形而上学的残余，应当被抛弃。",
        "反映论是一种机械唯物主义的认识论，忽视了认识的主体建构性。",
        "阶级不是客观的经济位置，而是话语领导权争夺的结果。",
        "社会主义不是历史发展的必然结果，而是政治斗争的偶然产物。",
        "马克思的哲学不是唯物主义，而是实践哲学或人学。",
        "意识不是人脑的机能，而是语言的产物。",
        "生产力决定生产关系是一种技术决定论，忽视了政治和文化的自主性。",
        "剩余价值理论已经过时，无法解释当代资本主义的信息经济。",
        "马克思主义是一种宏大叙事，在后现代条件下已经失效。",
        "实践不是物质活动，而是意义建构的活动。",
    ]

    # ===== 困难负样本：似是而非(hard_negative) =====
    hard_negative_samples = [
        "实践是主体能动地改造客体的活动，但这种能动性意味着意识可以超越物质的限制。",
        "虽然物质决定意识，但在某些特殊情况下，意识可以决定物质。",
        "矛盾的斗争性是绝对的，同一性是相对的，因此斗争性比同一性更重要。",
        "真理是客观的，但每个人的真理都是不同的，所以真理没有客观标准。",
        "经济基础决定上层建筑，但上层建筑中的意识形态具有完全独立的自主性。",
        "马克思主义强调人的主体性，这意味着人可以选择不受客观规律的制约。",
        "实践是检验真理的标准，但逻辑证明有时也可以作为检验真理的标准。",
        "社会存在决定社会意识，但艺术家的创作灵感完全来自个人天赋，与社会存在无关。",
        "物质是运动的，但运动可以脱离物质而存在，如精神运动。",
        "矛盾无处不在，因此和谐是不存在的，社会只能在矛盾冲突中发展。",
        "认识来源于实践，但书本知识也是认识的来源，所以实践不是唯一来源。",
        "生产力决定生产关系，但生产关系可以长期落后于生产力而不影响社会发展。",
        "人民群众创造历史，但英雄人物可以决定历史发展的方向。",
        "真理具有相对性，所以任何真理都是相对的，不存在绝对真理。",
        "价值是客观的，但审美价值完全取决于个人的主观感受。",
    ]

    # ===== 中性样本(neutral) =====
    neutral_samples = [
        "马克思主义哲学包括辩证唯物主义和历史唯物主义两个组成部分。",
        "费尔巴哈是德国古典哲学的代表人物之一。",
        "《资本论》全书共三卷，分别研究资本的生产过程、流通过程和资本主义生产的总过程。",
        "马克思生于1818年，恩格斯生于1820年。",
        "辩证唯物主义和历史唯物主义是马克思主义的世界观和方法论。",
        "哲学基本问题包括两个方面：思维和存在何者为第一性，思维能否认识存在。",
        "德国古典哲学的主要代表人物是康德、费希特、谢林、黑格尔和费尔巴哈。",
        "马克思主义政治经济学的研究对象是生产关系及其发展规律。",
        "科学社会主义是马克思主义理论体系的核心。",
        "《共产党宣言》发表于1848年2月。",
    ]

    for text in orthodox_samples:
        data.append({"text": text, "label": 1, "category": "orthodox", "hard": False})
    for text in deviation_samples:
        data.append({"text": text, "label": 2, "category": "deviation", "hard": False})
    for text in hard_negative_samples:
        data.append({"text": text, "label": 2, "category": "deviation", "hard": True})
    for text in neutral_samples:
        data.append({"text": text, "label": 0, "category": "neutral", "hard": False})

    return data

# ============================================================
# 3. 数据集类
# ============================================================

class StanceDataset(Dataset):
    def __init__(self, data, tokenizer, max_length=256):
        self.data = data
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        item = self.data[idx]
        text = item["text"]
        label = item["label"]

        encoding = self.tokenizer(
            text,
            max_length=self.max_length,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )

        return {
            "input_ids": encoding["input_ids"].squeeze(0),
            "attention_mask": encoding["attention_mask"].squeeze(0),
            "label": torch.tensor(label, dtype=torch.long),
            "text": text,
            "hard": item.get("hard", False)
        }

# ============================================================
# 4. Focal Loss（处理类别不平衡）
# ============================================================

class FocalLoss(nn.Module):
    """
    Focal Loss for imbalanced classification
    对困难样本（hard negatives）给予更高权重
    """
    def __init__(self, alpha=None, gamma=2.0, reduction="mean"):
        super(FocalLoss, self).__init__()
        self.alpha = alpha  # 类别权重
        self.gamma = gamma
        self.reduction = reduction
        self.ce = nn.CrossEntropyLoss(reduction="none")

    def forward(self, inputs, targets):
        ce_loss = self.ce(inputs, targets)
        pt = torch.exp(-ce_loss)

        if self.alpha is not None:
            alpha_t = self.alpha[targets]
            focal_loss = alpha_t * (1 - pt) ** self.gamma * ce_loss
        else:
            focal_loss = (1 - pt) ** self.gamma * ce_loss

        if self.reduction == "mean":
            return focal_loss.mean()
        elif self.reduction == "sum":
            return focal_loss.sum()
        return focal_loss

# ============================================================
# 5. 模型定义
# ============================================================

class StanceClassifier(nn.Module):
    def __init__(self, config, bert_model):
        super(StanceClassifier, self).__init__()
        self.bert = bert_model
        self.dropout = nn.Dropout(config.hidden_dropout_prob)
        self.classifier = nn.Linear(self.bert.config.hidden_size, config.num_classes)

        # 初始化分类层
        nn.init.normal_(self.classifier.weight, std=0.02)
        nn.init.zeros_(self.classifier.bias)

    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        # 取[CLS] token的表示
        pooled_output = outputs.last_hidden_state[:, 0, :]
        pooled_output = self.dropout(pooled_output)
        logits = self.classifier(pooled_output)
        return logits

# ============================================================
# 6. 训练工具函数
# ============================================================

def get_optimizer_and_scheduler(model, config, num_training_steps):
    """AdamW + Warmup + Linear Decay"""
    from transformers import AdamW, get_linear_schedule_with_warmup

    # 分层学习率：BERT层用较小lr，分类层用较大lr
    no_decay = ["bias", "LayerNorm.weight"]
    optimizer_grouped_parameters = [
        {
            "params": [p for n, p in model.named_parameters() if not any(nd in n for nd in no_decay)],
            "weight_decay": config.weight_decay,
            "lr": config.learning_rate,
        },
        {
            "params": [p for n, p in model.named_parameters() if any(nd in n for nd in no_decay)],
            "weight_decay": 0.0,
            "lr": config.learning_rate,
        },
        {
            "params": [p for n, p in model.named_parameters() if "classifier" in n],
            "weight_decay": config.weight_decay,
            "lr": config.learning_rate * 5,  # 分类头学习率更高
        }
    ]

    optimizer = AdamW(optimizer_grouped_parameters, lr=config.learning_rate)

    num_warmup_steps = int(num_training_steps * config.warmup_ratio)
    scheduler = get_linear_schedule_with_warmup(
        optimizer,
        num_warmup_steps=num_warmup_steps,
        num_training_steps=num_training_steps
    )

    return optimizer, scheduler

def evaluate(model, dataloader, device):
    """评估函数"""
    model.eval()
    all_preds = []
    all_labels = []
    all_texts = []

    with torch.no_grad():
        for batch in dataloader:
            input_ids = batch["input_ids"].to(device)
            attention_mask = batch["attention_mask"].to(device)
            labels = batch["label"].to(device)

            logits = model(input_ids, attention_mask)
            preds = torch.argmax(logits, dim=1)

            all_preds.extend(preds.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())
            all_texts.extend(batch["text"])

    # 计算指标
    precision, recall, f1, support = precision_recall_fscore_support(
        all_labels, all_preds, average=None, labels=[0, 1, 2]
    )
    accuracy = np.mean(np.array(all_preds) == np.array(all_labels))

    # 特别关注deviation类的召回率（不能漏掉非正统内容）
    deviation_recall = recall[2] if len(recall) > 2 else 0.0

    metrics = {
        "accuracy": accuracy,
        "neutral_precision": precision[0],
        "orthodox_precision": precision[1],
        "deviation_precision": precision[2],
        "deviation_recall": deviation_recall,
        "macro_f1": np.mean(f1),
    }

    return metrics, all_preds, all_labels, all_texts

def print_misclassified(all_texts, all_preds, all_labels, id2label):
    """打印误分类样本，用于专家审核"""
    print("\n" + "="*60)
    print("误分类样本分析（用于专家审核）")
    print("="*60)

    for text, pred, label in zip(all_texts, all_preds, all_labels):
        if pred != label:
            print(f"\n[真实: {id2label[label]} | 预测: {id2label[pred]}]")
            print(f"文本: {text[:80]}...")

# ============================================================
# 7. 主训练流程
# ============================================================

def main():
    config = Config()
    os.makedirs(config.output_dir, exist_ok=True)

    print(f"设备: {config.device}")
    print(f"输出目录: {config.output_dir}")

    # 检查transformers是否可用
    try:
        from transformers import BertTokenizer, BertModel, AdamW, get_linear_schedule_with_warmup
        HAS_TRANSFORMERS = True
    except ImportError:
        HAS_TRANSFORMERS = False
        print("警告: transformers库未安装，将使用模拟模式演示Pipeline结构")
        print("生产环境请执行: pip install transformers")

    # 构建数据
    data = build_seed_dataset()
    print(f"\n数据集统计:")
    label_dist = Counter([d["label"] for d in data])
    print(f"  neutral(0): {label_dist[0]}")
    print(f"  orthodox(1): {label_dist[1]}")
    print(f"  deviation(2): {label_dist[2]}")

    # 划分训练/验证/测试
    train_data, temp_data = train_test_split(data, test_size=0.3, random_state=42, stratify=[d["label"] for d in data])
    val_data, test_data = train_test_split(temp_data, test_size=0.5, random_state=42, stratify=[d["label"] for d in temp_data])

    print(f"\n数据划分: 训练{len(train_data)} / 验证{len(val_data)} / 测试{len(test_data)}")

    if not HAS_TRANSFORMERS:
        print("\n" + "="*60)
        print("模拟模式：Pipeline结构展示完毕")
        print("="*60)
        print("""
生产环境执行步骤：
1. pip install transformers scikit-learn torch
2. 准备大规模标注数据（建议每类≥5000条）
3. 运行 python bert_stance_classifier.py
4. 模型将保存至 ./stance_model_output/best_model.pt
5. 部署时使用 torch.jit.trace 或 onnx 导出推理模型
        """)
        return

    # 加载Tokenizer和模型
    print(f"\n加载模型: {config.model_name}")
    tokenizer = BertTokenizer.from_pretrained(config.model_name)
    bert_model = BertModel.from_pretrained(config.model_name)

    # 构建数据集
    train_dataset = StanceDataset(train_data, tokenizer, config.max_length)
    val_dataset = StanceDataset(val_data, tokenizer, config.max_length)
    test_dataset = StanceDataset(test_data, tokenizer, config.max_length)

    # 类别权重采样（解决imbalance）
    train_labels = [d["label"] for d in train_data]
    class_counts = Counter(train_labels)
    class_weights = {k: 1.0/v for k, v in class_counts.items()}
    sample_weights = [class_weights[label] for label in train_labels]
    sampler = WeightedRandomSampler(sample_weights, len(sample_weights), replacement=True)

    train_loader = DataLoader(train_dataset, batch_size=config.batch_size, sampler=sampler)
    val_loader = DataLoader(val_dataset, batch_size=config.batch_size, shuffle=False)
    test_loader = DataLoader(test_dataset, batch_size=config.batch_size, shuffle=False)

    # 初始化模型
    model = StanceClassifier(config, bert_model).to(config.device)

    # 损失函数
    alpha_tensor = torch.tensor(config.focal_alpha, dtype=torch.float).to(config.device)
    criterion = FocalLoss(alpha=alpha_tensor, gamma=config.focal_gamma)

    # 优化器与调度器
    num_training_steps = len(train_loader) * config.epochs
    optimizer, scheduler = get_optimizer_and_scheduler(model, config, num_training_steps)

    # 训练循环
    best_deviation_recall = 0.0
    id2label = {0: "neutral", 1: "orthodox", 2: "deviation"}

    print("\n开始训练...")
    for epoch in range(config.epochs):
        model.train()
        total_loss = 0

        for batch_idx, batch in enumerate(train_loader):
            input_ids = batch["input_ids"].to(config.device)
            attention_mask = batch["attention_mask"].to(config.device)
            labels = batch["label"].to(config.device)

            optimizer.zero_grad()
            logits = model(input_ids, attention_mask)
            loss = criterion(logits, labels)

            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), config.grad_clip)
            optimizer.step()
            scheduler.step()

            total_loss += loss.item()

            if batch_idx % 10 == 0:
                print(f"  Epoch {epoch+1}/{config.epochs} | Batch {batch_idx}/{len(train_loader)} | Loss: {loss.item():.4f}")

        avg_loss = total_loss / len(train_loader)

        # 验证
        val_metrics, val_preds, val_labels, val_texts = evaluate(model, val_loader, config.device)
        print(f"\nEpoch {epoch+1} 验证结果:")
        print(f"  Loss: {avg_loss:.4f}")
        print(f"  Accuracy: {val_metrics['accuracy']:.4f}")
        print(f"  Orthodox Precision: {val_metrics['orthodox_precision']:.4f}")
        print(f"  Deviation Precision: {val_metrics['deviation_precision']:.4f}")
        print(f"  Deviation Recall: {val_metrics['deviation_recall']:.4f} (关键指标)")
        print(f"  Macro F1: {val_metrics['macro_f1']:.4f}")

        # 保存最佳模型（以deviation_recall为关键指标）
        if val_metrics["deviation_recall"] > best_deviation_recall:
            best_deviation_recall = val_metrics["deviation_recall"]
            torch.save({
                "epoch": epoch + 1,
                "model_state_dict": model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "metrics": val_metrics,
                "config": vars(config)
            }, config.best_model_path)
            print(f"  >>> 保存最佳模型 (deviation_recall={best_deviation_recall:.4f})")

    # 最终测试
    print("\n" + "="*60)
    print("最终测试评估")
    print("="*60)

    checkpoint = torch.load(config.best_model_path)
    model.load_state_dict(checkpoint["model_state_dict"])

    test_metrics, test_preds, test_labels, test_texts = evaluate(model, test_loader, config.device)

    print(f"\n测试集结果:")
    print(f"  Accuracy: {test_metrics['accuracy']:.4f}")
    print(f"  Macro F1: {test_metrics['macro_f1']:.4f}")
    print(f"  Deviation Recall: {test_metrics['deviation_recall']:.4f}")

    print("\n详细分类报告:")
    print(classification_report(test_labels, test_preds, target_names=["neutral", "orthodox", "deviation"]))

    print("\n混淆矩阵:")
    print(confusion_matrix(test_labels, test_preds))

    # 打印误分类
    print_misclassified(test_texts, test_preds, test_labels, id2label)

    # 导出模型为推理格式
    print("\n导出推理模型...")
    model.eval()
    dummy_input_ids = torch.zeros(1, config.max_length, dtype=torch.long).to(config.device)
    dummy_attention_mask = torch.ones(1, config.max_length, dtype=torch.long).to(config.device)

    traced_model = torch.jit.trace(
        lambda x, y: model(x, y),
        (dummy_input_ids, dummy_attention_mask)
    )
    traced_model.save(os.path.join(config.output_dir, "stance_classifier_traced.pt"))
    print(f"推理模型已保存至: {config.output_dir}/stance_classifier_traced.pt")

    # 保存tokenizer
    tokenizer.save_pretrained(config.output_dir)
    print(f"Tokenizer已保存至: {config.output_dir}")

# ============================================================
# 8. 推理接口（生产环境调用）
# ============================================================

class StancePredictor:
    """
    生产环境推理接口
    用法:
        predictor = StancePredictor(model_path, tokenizer_path)
        result = predictor.predict("文本内容")
        # result = {"label": "orthodox", "confidence": 0.98, "is_safe": True}
    """
    def __init__(self, model_path, tokenizer_path, device="cpu"):
        from transformers import BertTokenizer
        self.tokenizer = BertTokenizer.from_pretrained(tokenizer_path)
        self.model = torch.jit.load(os.path.join(model_path, "stance_classifier_traced.pt"))
        self.model.to(device)
        self.model.eval()
        self.device = device
        self.id2label = {0: "neutral", 1: "orthodox", 2: "deviation"}
        self.label2zh = {"neutral": "中性", "orthodox": "正统", "deviation": "偏离"}

    def predict(self, text, return_probs=False):
        encoding = self.tokenizer(
            text,
            max_length=256,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )

        input_ids = encoding["input_ids"].to(self.device)
        attention_mask = encoding["attention_mask"].to(self.device)

        with torch.no_grad():
            logits = self.model(input_ids, attention_mask)
            probs = F.softmax(logits, dim=1)
            pred_id = torch.argmax(probs, dim=1).item()
            confidence = probs[0][pred_id].item()

        label = self.id2label[pred_id]

        result = {
            "label": label,
            "label_zh": self.label2zh[label],
            "confidence": round(confidence, 4),
            "is_safe": label != "deviation" and confidence > 0.85,
            "all_probs": {
                self.id2label[i]: round(probs[0][i].item(), 4) 
                for i in range(3)
            } if return_probs else None
        }

        return result

if __name__ == "__main__":
    main()
