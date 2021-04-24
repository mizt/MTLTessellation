# MTLTessellation

## Tessellation - Apple Developer

[https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Tessellation/Tessellation.html](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Tessellation/Tessellation.html)

**対応機種:** iOS_GPUFamily3_v2, OSX_GPUFamily1_v2

テッセレーションは、制御点で構成された四角形または三角形のパッチで構築された初期サーフェスから、より詳細なサーフェスを計算するために使用されます。高次のサーフェスを近似するために、GPUはパッチごとのテッセレーション係数を使用して、各パッチを三角形に細分化します。

### Metalテッセレーションパイプライン

Figure 12-1は、Metalテッセレーションパイプラインを示しており、コンピュートカーネル、テッセレータ、ポストテッセレーション頂点関数を使用しています。

**Figure 12-1**  Metalテッセレーションパイプライン

![](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Art/Tessellation_Pipeline_2x.png)

テッセレーションはパッチで動作し、各パッチはコントロールポイントのコレクションによって定義されたジオメトリの任意の配置を表します。パッチごとのテッセレーション係数、パッチごとのユーザーデータ、およびパッチコントロールポイントデータは、それぞれ個別の[MTLBuffer](https://developer.apple.com/documentation/metal/mtlbuffer)オブジェクトに格納されます。

#### コンピュートカーネル

コンピュートカーネルは、次の操作を実行する「カーネル関数」です。

- パッチごとのテッセレーション係数を計算します。
- オプションで、パッチごとのユーザーデータを計算します。
- オプションで、パッチコントロールポイントデータを計算または変更します。

**Note:** パッチごとのテッセレーション係数、パッチごとのユーザーデータ、パッチのコントロールポイントデータを計算するために、コンピュートカーネルをフレームごとに実行する必要はありません。必要なときにテッセレーションとポストテッセレーション頂点関数に必要なデータを供給する限り、これらのデータを `n`フレームごとに、オフラインまたはその他のランタイム手段で計算することができます。

#### テッセレータ

テッセレータは，パッチ表面のサンプリングパターンを作成し，これらのサンプルを接続するグラフィックスプリミティブを生成する「固定機能パイプラインステージ」です。テッセレータは、正規化された座標系で`0.0`から`1.0`の範囲のカノニカルドメインをタイル化します。

テッセレータはレンダーパイプラインの一部として構成され[MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor)オブジェクトを使用して[MTLRenderPipelineState](https://developer.apple.com/documentation/metal/mtlrenderpipelinestate)オブジェクトを構築します。テッセレータへの入力は、パッチごとのテッセレーション因子です。

##### テッセレータのプリミティブ生成

テッセレータは、パッチごとに1回実行され、入力パッチを消費して、新しい三角形のセットを生成します。これらの三角形は、提供されたパッチごとのテッセレーション係数に従って、パッチを細分化して生成されます。テッセレータによって生成された各三角形の頂点には、正規化されたパラメータ空間における(u, v)または(u, v, w)の位置が関連付けられており、各パラメータ値は`0.0`から`1.0`の範囲にあります。(細分化は実装に依存した方法で行われることに注意してください)

#### ポストテッセレーション頂点関数

ポストテッセレーション頂点関数は、テッセレータで生成された各パッチ面サンプルの頂点データを計算する頂点関数です。ポストテッセレーション頂点関数の入力は以下の通りです。

* パッチ上の正規化された頂点座標。（テッセレータによって出力されます）
* パッチごとのユーザデータ。（コンピュートカーネルが任意に出力します）
* パッチの制御点データ。（コンピュートカーネルが任意に出力します）
* テクスチャやバッファなど、その他の頂点関数の入力。

ポストテッセレーション頂点関数は、テッセレーションされた三角形の最終的な頂点データを生成します。ポストテッセレーション頂点関数の実行が完了すると、テッセレーションされたプリミティブがラスタライズされ、レンダリングパイプラインの残りのステージが通常通り実行されます。

### パッチごとのテッセレーション因子

パッチごとのテッセレーション因子は、テッセレータによって各パッチがどれだけ細分化されるかを指定します。パッチごとのテッセレーション因子は、クワッドパッチの場合は[MTLQuadTessellationFactorsHalf](https://developer.apple.com/documentation/metal/mtlquadtessellationfactorshalf)構造体、トライアングルパッチの場合は[MTLTriangleTessellationFactorsHalf](https://developer.apple.com/documentation/metal/mtltriangletessellationfactorshalf)構造体で記述します。

**Note:** 構造体のメンバーは`uint16_t`型ですが、テッセレータに供給されるパッチごとのテッセレーション係数は`half`型でなければなりません。

#### クワッドパッチについて

クワッドパッチの場合、パッチ内の位置は、Figure 12-2に示すように、クワッドパッチの境界に対する頂点の水平および垂直方向の位置を示す (u, v)カーテシアン座標です。 (u, v)の値はそれぞれ`0.0` から`1.0`の範囲です。

**Figure 12-2**  正規化されたパラメータ空間におけるクワッドパッチ座標

![](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Art/Tessellation_QuadFactors_2x.png)

#### MTLQuadTessellationFactorsHalf構造体の解釈について

[MTLQuadTessellationFactorsHalf](https://developer.apple.com/documentation/metal/mtlquadtessellationfactorshalf)構造体の定義は以下の通りです。

```
typedef struct {
    uint16_t edgeTessellationFactor[4];
    uint16_t insideTessellationFactor[2];
} MTLQuadTessellationFactorsHalf;
```

 この構造体の各値は、特定のテッセレーション因子を提供します。

- `edgeTessellationFactor[0]`は`u=0` (edge 0)であるパッチのエッジに対するテッセレーション因子を提供します。
- `edgeTessellationFactor[1]`は`u=1` (edge 1)であるパッチのエッジに対するテッセレーション因子を提供します。
- `edgeTessellationFactor[2]`は`u=2` (edge 2)であるパッチのエッジに対するテッセレーション因子を提供します。
- `edgeTessellationFactor[3]`は`u=3` (edge 3)であるパッチのエッジに対するテッセレーション因子を提供します。
- `insideTessellationFactor[0]`は`v`のすべての内部値に対する水平方向のテッセレーション因子を提供します。
- `insideTessellationFactor[1]`は`u`のすべての内部値に対する垂直方向のテッセレーション因子を提供します。

#### パッチの廃棄ルール

エッジのテッセレーション因子の値が負であるか、ゼロであるか、浮動小数点の`NaN`に相当する場合、テッセレータはパッチを破棄します。内側のテッセレーション因子の値が負の場合、テッセレーション因子は[tessellationPartitionMode](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor/1639979-tessellationpartitionmode)プロパティで定義された範囲にクランプされ、テッセレータはパッチを破棄しません。

パッチが廃棄されず[tessellationFactorScaleEnabled](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor/1640045-istessellationfactorscaleenabled)プロパティが`YES`に設定されている場合、テッセレータはエッジとインサイドのテッセレーション因子に[setTessellationFactorScale:](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1639992-settessellationfactorscale)メソッドで指定されたスケール因子を乗算します。

パッチが破棄されると、新しいプリミティブは生成されず、ポストテッセレーション頂点関数は実行されず、そのパッチの可視出力は生成されません。

#### パッチごとのテッセレーション因子バッファの指定

パッチごとのテッセレーション因子は[MTLBuffer](https://developer.apple.com/documentation/metal/mtlbuffer)オブジェクトに書き込まれ[setTessellationFactorBuffer:offset:instanceStride:](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1640035-settessellationfactorbuffer)メソッドを呼び出すことで、テッセレータへの入力として渡されます。このメソッドは、同じ[MTLRenderCommandEncoder](https://developer.apple.com/documentation/metal/mtlrendercommandencoder)オブジェクトにパッチドローコールを発行する前に呼び出す必要があります。

### パッチ関数

このセクションでは、テッセレーションをサポートするためのMetal shading languageの主な変更点をまとめています。詳細については「Metal Shading Language Guide」の「Functions, Variables, and Qualifier」の章を参照してください。

#### コンピュートカーネルの作成

コンピュートカーネルは、既存のカーネル関数修飾子を使って識別されたカーネル関数です。Listing 12-1は、コンピュートカーネル関数シグネチャの例です。

**Listing 12-1** コンピュートカーネル関数シグネチャ

```
kernel void my_compute_kernel(...) {...}
```

コンピュートカーネルは、Metal シェーディング言語の既存の機能で完全にサポートされています。コンピュートカーネル関数の入力と出力は、通常のカーネル関数と同じです。

#### ポストテッセレーション頂点関数の作成

ポストテッセレーション頂点関数は、既存の頂点関数修飾子を使用して識別される頂点関数です。さらに、新しい`[[patch(patch-type), N]]`属性を使用して、パッチタイプ（`patch-type`）とパッチ内の制御点の数（`N`）を指定します。Listing 12-2は、ポストテッセレーション頂点関数シグネチャの例です。

**Listing 12-2** ポストテッセレーション頂点関数シグネチャ

```
[[patch(quad, 16)]]
vertex float4 my_post_tessellation_vertex_function(...) {...}
```

**Note:** OS Xでは、パッチ内のコントロールポイントの数を常に指定する必要があります。iOSとtvOSでは、この値の指定はオプションです。この値を指定した場合、パッチドローコールの`numberOfPatchControlPoints`パラメータの値と一致しなければなりません。

##### ポストテッセレーション頂点関数の入力

 ポストテッセレーション頂点関数へのすべての入力は、以下の1つまたは複数の引数として渡されます。

- バッファ（`device`または`constant`のアドレス空間で宣言されている）、テクスチャ、またはサンプラーなどのリソース。
- パッチごとのデータとパッチコントロールポイントのデータです。これらはバッファから直接読み込まれるか `[[stage_in]]` という修飾子で宣言された入力としてポストテッセレーション頂点関数に渡されます。
- Table 12-1.に記載されている組み込み変数。

**Table 12-1** ポストテッセレーション頂点関数の入力引数の属性修飾子

| Attribute qualifier     | Corresponding data type | Description                                                  |
| :---------------------- | :---------------------- | :----------------------------------------------------------- |
| `[[patch_id]]` | `ushort` or `uint` | パッチの識別子。                                             |
| `[[instance_id]]` | `ushort` or `uint` | インスタンスごとの識別子で、ベースとなるインスタンス値が指定されている場合はそれを含みます。 |
| `[[base_instance]]` | `ushort` or `uint` | インスタンスごとのデータを読み込む前に、各インスタンス識別子に追加されるベースとなるインスタンス値。 |
| `[[position_in_patch]]` | `float2` or `float3` | 評価されるパッチ上の位置を定義します。クワッドパッチでは`float2`でなければなりません。トライアングルパッチの場合は `float3`としてください。 |

##### ポストテッセレーション頂点関数の出力

ポストテッセレーション頂点関数の出力は、通常の頂点関数と同じです。ポストテッセレーション頂点関数がバッファに書き込む場合、その戻り値の型は`void`でなければなりません。

### テッセレーションパイプラインの状態

このセクションでは、テッセレーションをサポートするためのMetalフレームワークAPIの主な変更点を、テッセレーションパイプラインの状態に関連してまとめています。

#### コンピュートパイプラインの構築

Listing 12-3で示されているように、コンピュートカーネルは[MTLComputePipelineState](https://developer.apple.com/documentation/metal/mtlcomputepipelinestate)オブジェクトを構築するときに、コンピュートパイプラインの一部として指定されます。最高のパフォーマンスを得るために、コンピュートカーネルはフレームの中でできる限り早く実行されるべきです。（コンピュートカーネルやテッセレーションをサポートするために、既存のコンピュートパイプラインAPIを変更する必要はありません）

**Listing 12-3** コンピュートカーネルによるコンピュートパイプラインの構築

```
// Fetch the compute kernel from the library
id <MTLFunction> computeKernel = [_library newFunctionWithName:@"my_compute_kernel"];
 
// Build the compute pipeline
NSError *pipelineError = NULL;
_computePipelineState = [_device newComputePipelineStateWithFunction:computeKernel error:&pipelineError];
if (!_computePipelineState) {
    NSLog(@"Failed to create compute pipeline state, error: %@", pipelineError);
}
```

#### レンダーパイプラインの構築

テッセレータはレンダーパイプラインの一部として構成され[MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor)オブジェクトを使用して[MTLRenderPipelineState](https://developer.apple.com/documentation/metal/mtlrenderpipelinestate)オブジェクトを構築します。ポストテッセレーション頂点関数は[vertexFunction](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor/1514679-vertexfunction)プロパティで指定されます。Listing 12-4はテッセレータとポストテッセレーション頂点関数を使ってレンダーパイプラインを設定、構築する方法を示しています。詳細については[MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor)クラスリファレンスの「Specifying Tessellation State」と[MTLTessellationFactorStepFunction](https://developer.apple.com/documentation/metal/mtltessellationfactorstepfunction)のセクションを参照してください。

**Listing 12-4** テッセレータとポストテッセレーション頂点関数によるレンダリングパイプラインの構築

```
// Fetch the post-tessellation vertex function from the library
id <MTLFunction> postTessellationVertexFunction = [_library newFunctionWithName:@"my_post_tessellation_vertex_function"];
 
// Fetch the fragment function from the library
id <MTLFunction> fragmentFunction = [_library newFunctionWithName:@"my_fragment_function"];
 
// Configure the render pipeline, using the default tessellation values
MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
renderPipelineDescriptor.colorAttachments[0].pixelFormat = _view.colorPixelFormat;
renderPipelineDescriptor.fragmentFunction = fragmentFunction;
renderPipelineDescriptor.vertexFunction = postTessellationVertexFunction;
renderPipelineDescriptor.maxTessellationFactor = 16;
renderPipelineDescriptor.tessellationFactorScaleEnabled = NO;
renderPipelineDescriptor.tessellationFactorFormat = MTLTessellationFactorFormatHalf;
renderPipelineDescriptor.tessellationControlPointIndexType = MTLTessellationControlPointIndexTypeNone;
renderPipelineDescriptor.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionConstant;
renderPipelineDescriptor.tessellationOutputWindingOrder = MTLWindingClockwise;
renderPipelineDescriptor.tessellationPartitionMode = MTLTessellationPartitionModePow2;
 
// Build the render pipeline
NSError *pipelineError = NULL;
_renderPipelineState = [_device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&pipelineError];
if (!_renderPipelineState) {
    NSLog(@"Failed to create render pipeline state, error %@", pipelineError);
}
```

### パッチドローコール

このセクションでは、テッセレーションをサポートするためのMetalフレームワークAPIの主な変更点を、パッチドローコールに関連してまとめています。

#### テッセレーションされたパッチの描画

テッセレーションされたパッチの多数のインスタンスをレンダリングするには、これらの[MTLRenderCommandEncoder](https://developer.apple.com/documentation/metal/mtlrendercommandencoder)メソッドのいずれかを呼び出します。

- [drawPatches:patchStart:patchCount:patchIndexBuffer:patchIndexBufferOffset:instanceCount:baseInstance:](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1639984-drawpatches)
- [drawPatches:patchIndexBuffer:patchIndexBufferOffset:indirectBuffer:indirectBufferOffset:](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1639895-drawpatches)
- [drawIndexedPatches:patchStart:patchCount:patchIndexBuffer:patchIndexBufferOffset:controlPointIndexBuffer:controlPointIndexBufferOffset:instanceCount:baseInstance:](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1640031-drawindexedpatches)
- [drawIndexedPatches:patchIndexBuffer:patchIndexBufferOffset:controlPointIndexBuffer:controlPointIndexBufferOffset:indirectBuffer:indirectBufferOffset:](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/1639949-drawindexedpatches)

**Note:** これらのパッチドローコールは[vertexFunction](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor/1514679-vertexfunction)プロパティにポストテッセレーション頂点関数が設定されている場合にのみ呼び出すことができます。パッチドローコールでないものを呼び出すと、検証レイヤーがエラーを報告します。

パッチドローコールはプリミティブリスタート機能をサポートしていません。

すべてのパッチの描画コールでは、パッチごとのデータとパッチ制御点の配列が`baseInstance`パラメータで指定された値を起点に、連続した配列要素でレンダリングされるように編成されます。各パラメータの詳細については[MTLRenderCommandEncoder](https://developer.apple.com/documentation/metal/mtlrendercommandencoder)プロトコルリファレンスの「Drawing Tessellated Patches」のセクションを参照してください。

パッチデータをレンダリングするために、パッチドローコールはパッチごとのデータとパッチコントロールポイントのデータを取得します。パッチデータは通常、1つまたは複数のメッシュのすべてのパッチについて、1つまたは複数のバッファにまとめて保存されます。コンピュートカーネルは、シーンに依存したパッチごとのテッセレーション係数を生成するために実行されます。コンピュートカーネルは、破棄されないパッチに対してのみ係数を生成することを決定することができ、その場合にはパッチは連続していません。そのため、描画されるパッチのパッチIDを特定するために、パッチインデックスバッファが使用されます。

データの参照には`[patchStart, patchStart+patchCount-1]`の範囲のバッファインデックス（`drawPatchIndex`）が使用されます。パッチごとのデータやパッチコントロールポイントのデータを取得するのに使われるパッチインデックスが連続していない場合は、Figure 12-4に示すように`drawPatchIndex`は`patchIndexBuffer`を参照することができます。

**Figure 12-4** パッチごとのデータやパッチコントロールポイントのデータを取得するための`patchIndexBuffer`の使用

![](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Art/Tessellation_PatchIndexBuffer_2x.png)

`patchIndexBuffer`の各要素は、パッチごとのデータとパッチコントロールポイントのデータを参照する32ビットの`patchIndex`値を含みます。`patchIndexBuffer`から取得された`patchIndex`は`(drawPatchIndex * 4) + patchIndexBufferOffset`の位置にあります。

パッチのコントロールポイントのインデックスは次のように計算されます。

`patchIndex * numberOfPatchControlPoints * ((patchIndex + 1) * numberOfPatchControlPoints) - 1`

また`patchIndexBuffer`は、パッチごとのデータやパッチ制御点データを読み込むのに使う`patchIndex`を、パッチごとのテッセレーション因子を読み込むのに使うインデックスとは異なるものにすることを可能にします。テッセレータでは`drawPatchIndex`は、パッチごとのテッセレーション因子を取得するためのインデックスとして直接使用されます。

`patchIndexBuffer`が`NULL`の場合、Figure 12-5に示すように`drawPatchIndex`と`patchIndex`は同じ値になります。

**Figure 12-5**  `patchIndexBuffer`が `NULL`の場合、パッチごとのデータとパッチコントロールポイントのデータの取得

![](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Art/Tessellation_Null_2x.png)

制御点がパッチ間で共有されている場合や、パッチの制御点データが連続していない場合には`drawIndexedPatches`メソッドを使用します。`patchIndex`は指定された`controlPointIndexBuffer`を参照します。このバッファには、Figure 12-6に見られるように、パッチのコントロールポイントのインデックスが含まれています。（`tessellationControlPointIndexType`は`controlPointIndexBuffer`内のコントロールポイントインデックスのサイズを記述し`MTLTessellationControlPointIndexTypeUInt16`または`MTLTessellationControlPointIndexTypeUInt32`のいずれかでなければなりません）

**Figure 12-6** `controlPointIndexBuffer`を使用してパッチの制御点データの取得

![](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Art/Tessellation_ControlPointIndexBuffer_2x.png)

`controlPointIndexBuffer`内の最初のコントロールポイントインデックスの実際の位置は、次のように計算されます。

`controlPointIndexBufferOffset + (patchIndex * numberOfPatchControlPoints * controlPointIndexType == UInt16 ? 2 : 4)`

複数（`numberOfPatchControlPoints`）の制御点インデックスを、最初の制御点インデックスの位置から連続して`controlPointIndexBuffer`に格納する必要があります。

### サンプルコード

基本的なテッセレーションのパイプラインを設定する例としては[MetalBasicTessellation](https://developer.apple.com/library/archive/samplecode/MetalBasicTessellation/Introduction/Intro.html)サンプルをご覧ください。
