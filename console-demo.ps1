param(
    [string]$InboxRoot = (Join-Path $PSScriptRoot 'sample'),
    [switch]$Snapshot
)
$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$Host.UI.RawUI.WindowTitle = '架空サンプル | AI協働コンソール試用版'
$routes = @{
    NOA = Join-Path $InboxRoot '受信箱_NOA'
    Codex = Join-Path $InboxRoot '受信箱_Codex'
}
foreach ($folder in $routes.Values) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "受信箱がありません: $folder" }
}
function Get-ReceiptIndex {
    $index=@{}
    $log=Join-Path $InboxRoot 'やり取り\ログ.jsonl'
    if (Test-Path -LiteralPath $log) {
        foreach ($line in [System.IO.File]::ReadLines($log,$utf8)) {
            try { $entry=$line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($entry.file -and ($entry.状態 -eq '既読' -or $entry.向き -eq '既読')) {
                $index[[string]$entry.file]=$true
            }
        }
    }
    return $index
}
function Get-ReceiptStatus($item) {
    if ($receiptIndex.ContainsKey($item.Name)) { return '既読記録あり（実行・完了未確認）' }
    if ($item.To -eq '保管' -or $item.To.EndsWith('(既読)')) { return '保管済み（受領記録未確認）' }
    return '配置済み（受領記録なし）'
}
function Get-Messages {
    $all = foreach ($to in @('NOA','Codex')) {
        Get-ChildItem -LiteralPath $routes[$to] -File -Filter '*.md' | ForEach-Object {
            [PSCustomObject]@{ To=$to; Name=$_.Name; Path=$_.FullName; Time=$_.LastWriteTime; Length=$_.Length }
        }
    }
    $archive=Join-Path $InboxRoot 'やり取り'
    if (Test-Path -LiteralPath $archive) {
        $all=@($all)+@(Get-ChildItem -LiteralPath $archive -File -Filter '*.md' | ForEach-Object {
            [PSCustomObject]@{ To='保管'; Name=$_.Name; Path=$_.FullName; Time=$_.LastWriteTime; Length=$_.Length }
        })
        foreach ($target in @('NOA','Codex')) {
            $subfolder=Join-Path $archive ($target+'宛')
            if (Test-Path -LiteralPath $subfolder) {
                $all=@($all)+@(Get-ChildItem -LiteralPath $subfolder -File -Filter '*.md' | ForEach-Object {
                    [PSCustomObject]@{ To=($target+'(既読)'); Name=$_.Name; Path=$_.FullName; Time=$_.LastWriteTime; Length=$_.Length }
                })
            }
        }
    }
    @($all | Sort-Object Time,Name)
}
function Get-Writer($item) {
    $body=Read-Message $item
    $match=[regex]::Match($body,'(?m)^(?:送り手|送信者)[:：]\s*(.+)$')
    if ($match.Success) {
        $writer=($match.Groups[1].Value.Trim() -split '。|宛先[:：]|,')[0].Trim()
        if ($writer.Length -gt 70) { $writer=$writer.Substring(0,70)+'…' }
        return $writer
    }
    return '未記載'
}
function Read-Message($item) {
    # Terminal control characters in external messages are never executed/rendered.
    $body = [System.IO.File]::ReadAllText($item.Path, $utf8)
    [regex]::Replace($body, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '')
}
function Draw($items) {
    Clear-Host
    Write-Host ' 架空サンプル  |  AI協働コンソール試用版' -ForegroundColor Cyan
    Write-Host (' 更新 ' + (Get-Date -Format 'HH:mm:ss') + ' / 実ファイルを2秒ごとに確認')
    Write-Host ' 受信箱への配置 ≠ AIの受領・実行・完了。内部思考は表示しません。' -ForegroundColor DarkYellow
    Write-Host ' 架空デモです / AIは接続されていません / 同梱sampleだけを利用します'
    Write-Host ('─' * 76)
    if (-not $items.Count) { Write-Host 'まだメッセージはありません。' }
    $start = [Math]::Max(0, $items.Count - 8)
    for ($i=$start; $i -lt $items.Count; $i++) {
        $m=$items[$i]
        Write-Host ("[{0}] 更新 {1:MM/dd HH:mm:ss} → {2}  {3}" -f ($i+1),$m.Time,$m.To,$m.Name) -ForegroundColor Green
        try {
            Write-Host ('書き手: '+(Get-Writer $m)) -ForegroundColor Cyan
            Write-Host ('状態: '+(Get-ReceiptStatus $m)) -ForegroundColor Yellow
            $preview = ((Read-Message $m) -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 3) -join "`n"
            if ($preview.Length -gt 260) { $preview=$preview.Substring(0,260)+'…' }
            Write-Host $preview
        } catch { Write-Host '読み取り中。次回更新で再確認します。' }
        Write-Host ''
    }
    Write-Host ('─' * 76)
    Write-Host '[V] 番号を指定して全文  [N] 試用メッセージを作成  [R] 更新  [Q] 閉じる'
    Write-Host 'この画面は連携窓口です。両AIの自動起動・強制停止は行いません。' -ForegroundColor DarkGray
}
function Send-ChairmanMessage {
    Write-Host "`n送り先: 1=Claude Code/NOA  2=Codex本部  3=両者  空欄=取消"
    $choice=Read-Host '送り先'
    $targets=switch ($choice) { '1' {@('NOA')} '2' {@('Codex')} '3' {@('NOA','Codex')} default {@()} }
    if (-not $targets.Count) { return }
    Write-Host '内容を入力してください。1行だけ「.」で送信、空本文なら取消。'
    $lines=[System.Collections.Generic.List[string]]::new()
    while ($true) {
        $line=Read-Host
        if ($line -eq '.') { break }
        $lines.Add($line)
    }
    $body=($lines -join "`n").Trim()
    if (-not $body) { return }
    $id=(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $name=$id+'_会長指示.md'
    $text="# 試用メッセージ（架空デモ）`n`nメッセージID: $id`n送信者: 試用者（ローカルデモで入力）`n送信日時: $(Get-Date -Format o)`n宛先: $($targets -join ', ')`n`n## 指示本文`n$body`n`n## 受領側への依頼`n受領時にこのIDを引用して担当・次の行動を返してください。両者宛てなら重複実行せず担当を分けてください。`n"
    foreach ($to in $targets) {
        $destination=Join-Path $routes[$to] $name
        $temporary=$destination+'.tmp'
        [System.IO.File]::WriteAllText($temporary,$text,$utf8)
        Move-Item -LiteralPath $temporary -Destination $destination
    }
    Write-Host ('受信箱に配置しました: '+$id+' / AIの受領は返答待ちです。') -ForegroundColor Green
    Start-Sleep -Seconds 2
}
if ($Snapshot) {
    $receiptIndex=Get-ReceiptIndex
    $messages=Get-Messages
    foreach ($m in $messages) {
        [PSCustomObject]@{destination=$m.To; filename=$m.Name; writer=(Get-Writer $m); status=(Get-ReceiptStatus $m); timestamp=$m.Time.ToString('o'); preview=((Read-Message $m) -split '\r?\n' | Select-Object -First 1)} | ConvertTo-Json -Compress
    }
    exit 0
}
$last=''
$refresh=$true
while ($true) {
    $receiptIndex=Get-ReceiptIndex
    $messages=Get-Messages
    $fingerprint=($messages | ForEach-Object { $_.Path+'|'+$_.Time.Ticks+'|'+$_.Length }) -join ';'
    $fingerprint+='|receipts:'+ (($receiptIndex.Keys | Sort-Object) -join ';')
    if ($refresh -or $fingerprint -ne $last) { Draw $messages; $last=$fingerprint; $refresh=$false }
    $until=(Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $until) {
        if ([Console]::KeyAvailable) {
            $key=[Console]::ReadKey($true).Key
            switch ($key) {
                'Q' { exit 0 }
                'R' { $refresh=$true }
                'N' { Send-ChairmanMessage; $refresh=$true }
                'V' {
                    $number=Read-Host '全文を表示する番号'
                    $n=0
                    if ([int]::TryParse($number,[ref]$n) -and $n -ge 1 -and $n -le $messages.Count) {
                        Clear-Host
                        Write-Host ($messages[$n-1].Name) -ForegroundColor Cyan
                        Write-Host (Read-Message $messages[$n-1])
                        Read-Host 'Enterで一覧へ戻る' | Out-Null
                    }
                    $refresh=$true
                }
            }
            break
        }
        Start-Sleep -Milliseconds 100
    }
}

