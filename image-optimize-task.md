DepthAnythingによる画像レイヤリングアプリで、深度推定後のマスク生成・切り抜き生成が遅い。現状はCPU上で `CGImage -> RGBA配列 -> Swift for loop -> CGImage` のような処理をしており、特にレイヤごとのcutout生成で無駄が大きい。

目標は、深度マップと入力画像をMetal textureとして扱い、Metal compute shaderでpreview / overlay / cutout texturesを生成する構成に移行すること。

理想構成:

```text
input image texture
depth texture
layer ranges buffer
  ↓
Metal compute shader
  ↓
preview texture / overlay texture / cutout textures
  ↓
SwiftUI表示
```

実装方針:

1. `DepthSamples.values` のようなCPU側の深度配列を作らない

   * 現在のようにdepth `CGImage` をRGBA配列へ展開して `[Double]` / `[UInt8]` に変換する処理は避ける。
   * Metal shaderには `depthTexture: MTLTexture` を渡す。
   * 可能なら、Depth Anything Core ML の出力 `CVPixelBuffer` から `CVMetalTextureCache` 経由で直接 `MTLTexture` を作る。
   * ただし段階実装として、まずは既存の `CGImage` から `MTLTexture` を作ってもよい。

2. cutoutはレイヤごとに出力テクスチャを作る

   * 最初は1回のcompute dispatchで全レイヤを同時出力しなくてよい。
   * `cutoutTexture0`, `cutoutTexture1`, ... のように、レイヤ数ぶん `MTLTexture` を用意する。
   * 各レイヤごとにshaderをdispatchして、そのレイヤのcutout textureを生成する。

3. cutout shaderの処理は「対象レイヤに属するか」だけを見る

   * CPU版でやっていた「各レイヤに元画像をコピーして、非所属部分を透明化する」方式は避ける。
   * 各pixelについて:

     * depthを読む
     * 対象レイヤの `lowerBound...upperBound` に入っているか判定
     * 範囲内なら input image のpixelを書く
     * 範囲外なら透明 `float4(0, 0, 0, 0)` を書く

   例:

```metal
kernel void makeCutout(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant float& lower [[buffer(0)]],
    constant float& upper [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    float4 inputColor = inputTexture.read(gid);
    float depth = depthTexture.read(gid).r;

    if (depth >= lower && depth < upper) {
        outputTexture.write(inputColor, gid);
    } else {
        outputTexture.write(float4(0.0), gid);
    }
}
```

4. depthのRGB平均はやめる

   * depth mapはカラー画像ではなく、各pixelにつき深度値1個として扱う。
   * もしdepth textureがRGBA形式でも、shaderでは `.r` チャンネルだけ読む。
   * つまり `depth = (r + g + b) / 3` ではなく `depth = depthTexture.read(gid).r` にする。
   * 可能ならdepth texture formatは `.r8Unorm`, `.r16Float`, `.r32Float` など単一チャンネルに寄せる。
   * Depth Anythingの出力の向きがUI上のFront/Farと逆なら、shader内またはtexture生成時に `depth = 1.0 - depth` を適用できるようにする。

5. preview / overlay 生成もMetal化する

   * cutout生成と別shaderでもよい。
   * 各pixelについてdepthから所属layerを決め、layer colorを書いた `previewTexture` を生成する。
   * `overlayTexture` は input image と layer color を opacity でblendする。
   * layer ranges / colors は buffer としてshaderに渡す。

6. UI操作中の生成物を分ける

   * depth境界をドラッグしている間は、全cutoutを毎回生成しない。
   * editing中:

     * preview / overlayのみ更新
   * editing終了後:

     * 全cutoutを生成
   * 表示ON/OFF変更時:

     * 必要なcutoutだけ生成
   * これによりMetal化後もUI応答性を安定させる。

7. 実装は既存CPU版をすぐ消さず、差し替え可能にする

   * 既存の `DepthLayerMasking` 相当を残しつつ、Metal版rendererを追加する。
   * 例:

     * `CPUDepthLayerRenderer`
     * `MetalDepthLayerRenderer`
   * ViewModel側からは共通interfaceで呼べるようにする。
   * まずはMetal版でcutout生成だけを置き換え、その後preview / overlayも移行する。

段階的な実装順:

- [x] 1. Metal rendererクラスを追加する
- [x] 2. `CGImage` から `MTLTexture` を作るユーティリティを追加する
- [x] 3. `makeCutout` compute shaderを追加する
- [x] 4. レイヤごとにcutout textureを生成し、最終的にSwiftUI表示用 `CGImage` / `NSImage` に変換する
- [x] 5. preview / overlay shaderを追加する
- [x] 6. drag中はpreview / overlayのみ、drag終了後にcutout生成するようViewModel/UIの呼び出しを分ける
- [x] 7. 可能ならDepth Anything Core ML出力の `CVPixelBuffer` を保持し、`CVMetalTextureCache` で直接 `MTLTexture` 化する経路に改善する

重要な注意点:

* まずは正しさ優先でよい。
* ただしCPU側でdepthをピクセル配列化する処理は最終的に排除する。
* depthはRGB平均ではなく `.r` のみ読む。
* cutoutは「元画像全コピー → 不要部分削除」ではなく、「対象範囲なら書く、範囲外なら透明」の方式にする。
* レイヤ数が可変なので、最初はレイヤごとdispatch方式が実装しやすい。
* 将来的に最適化する場合は、1dispatchで複数texture出力する方式や、表示中レイヤのみ生成する方式を検討する。
