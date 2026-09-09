# model.py
import torch
import torch.nn as nn
from torchvision.models import resnet18, ResNet18_Weights

# Index 0 is strictly reserved for CTC Blank (-)
CHARS = "-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ !\"'(),.:;?+@/-#*&"
CHAR_TO_IDX = {char: idx for idx, char in enumerate(CHARS)}
IDX_TO_CHAR = {idx: char for idx, char in enumerate(CHARS)}
NUM_CLASSES = len(CHARS)

class ResNet18_CRNN(nn.Module):
    def __init__(self, num_classes=NUM_CLASSES, hidden_size=256, pretrained=True):
        super().__init__()
        weights = ResNet18_Weights.DEFAULT if pretrained else None
        backbone = resnet18(weights=weights)
        
        self.conv1 = backbone.conv1
        self.bn1 = backbone.bn1
        self.relu = backbone.relu
        self.maxpool = backbone.maxpool
        self.layer1 = backbone.layer1
        self.layer2 = backbone.layer2
        
        # Preserve sequence width along horizontal axis
        self.layer3 = backbone.layer3
        self.layer3[0].conv1.stride = (2, 1)
        self.layer3[0].downsample[0].stride = (2, 1)

        self.layer4 = backbone.layer4
        self.layer4[0].conv1.stride = (2, 1)
        self.layer4[0].downsample[0].stride = (2, 1)
        
        self.bridge = nn.Linear(512, hidden_size)
        
        self.bilstm = nn.LSTM(
            input_size=hidden_size,
            hidden_size=hidden_size,
            num_layers=2,
            bidirectional=True,
            batch_first=True,
            dropout=0.2
        )
        self.classifier = nn.Linear(hidden_size * 2, num_classes)

    def forward(self, x):
        # x: (Batch, 3, 32, W)
        x = self.conv1(x)
        x = self.bn1(x)
        x = self.relu(x)
        x = self.maxpool(x)
        
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        
        # (Batch, 512, 1, TimeSteps) -> (Batch, TimeSteps, 512)
        x = x.squeeze(2).permute(0, 2, 1)
        x = self.bridge(x)
        x, _ = self.bilstm(x)
        logits = self.classifier(x)
        return logits
