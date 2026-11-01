import QtQuick
import qs

// бар: столбик у левого края, строка сверху (Theme.state.barAt); по центру поперёк. Только columns — rows Grid считает сам,
// иначе при смене края columns и rows меняются по очереди и на миг выходит 1×1 («more visible items than rows*columns» в лог).
// Отдельным файлом, не inline component: новый inline component ломает горячую перезагрузку («is not a type») до рестарта qs.
Grid {
    readonly property bool vert: Theme.state.barAt !== "top"
    columns: vert ? 1 : 99
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
