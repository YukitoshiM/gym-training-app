import io
import os
import threading
from pathlib import Path
from typing import Optional

from PIL import Image


DEFAULT_MODEL_DIR = Path(__file__).resolve().parent / "models" / "calorie_clip"
MODEL_DIR = Path(os.getenv("CALORIE_CLIP_MODEL_DIR", str(DEFAULT_MODEL_DIR)))


class CalorieCLIPRuntime:
    def __init__(self, model_dir: Path = MODEL_DIR) -> None:
        self.model_dir = model_dir
        self._model = None
        self._lock = threading.Lock()
        self._error: Optional[str] = None

    @property
    def weights_path(self) -> Path:
        return self.model_dir / "calorie_clip.pt"

    @property
    def installed(self) -> bool:
        return self.weights_path.exists() and (self.model_dir / "config.json").exists()

    @property
    def error(self) -> Optional[str]:
        return self._error

    def predict(self, image_bytes: bytes) -> float:
        model = self._load()
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        prediction = float(model.predict(image))
        return min(5_000.0, max(0.0, prediction))

    def _load(self):
        if self._model is not None:
            return self._model

        with self._lock:
            if self._model is not None:
                return self._model
            if not self.installed:
                raise RuntimeError(
                    f"CalorieCLIP model is not installed at {self.model_dir}. "
                    "Run ./install_calorie_clip.sh first."
                )

            try:
                import open_clip
                import torch
                import torch.nn as nn

                class RegressionHead(nn.Module):
                    def __init__(self) -> None:
                        super().__init__()
                        self.net = nn.Sequential(
                            nn.Linear(512, 512),
                            nn.BatchNorm1d(512),
                            nn.ReLU(),
                            nn.Dropout(0.4),
                            nn.Linear(512, 256),
                            nn.BatchNorm1d(256),
                            nn.ReLU(),
                            nn.Dropout(0.3),
                            nn.Linear(256, 64),
                            nn.ReLU(),
                            nn.Linear(64, 1),
                        )

                    def forward(self, features):
                        return self.net(features)

                class Model:
                    def __init__(self) -> None:
                        self.clip, _, self.preprocess = open_clip.create_model_and_transforms(
                            "ViT-B-32",
                            pretrained=None,
                        )
                        self.head = RegressionHead()
                        checkpoint = torch.load(
                            MODEL_DIR / "calorie_clip.pt",
                            map_location="cpu",
                            weights_only=False,
                        )
                        self.clip.load_state_dict(checkpoint["clip_state"])
                        self.head.load_state_dict(checkpoint["regressor_state"])
                        self.clip.eval()
                        self.head.eval()

                    def predict(self, image: Image.Image) -> float:
                        tensor = self.preprocess(image).unsqueeze(0)
                        with torch.inference_mode():
                            features = self.clip.encode_image(tensor).float()
                            return self.head(features).item()

                self._model = Model()
                self._error = None
                return self._model
            except Exception as error:
                self._error = str(error)
                raise


calorie_clip_runtime = CalorieCLIPRuntime()
